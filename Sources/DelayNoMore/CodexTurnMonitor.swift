import DelayCore
import Foundation

/// Reads only turn metadata through Codex's documented local protocol.
/// This class never starts/resumes a thread and never requests task items.
final class CodexTurnMonitor: @unchecked Sendable {
    private struct Tracked {
        let turn: String
        let started = Date()
        var nextPoll = Date()
    }
    private let queue = DispatchQueue(label: "com.delaynomore.turn-status")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var timer: DispatchSourceTimer?
    private var buffer = Data()
    private var tracked: [String: Tracked] = [:]
    private var requests: [Int: (String, String)] = [:]
    typealias UsageCompletion = @Sendable (AgentUsage?) -> Void
    /// Usage reads waiting for the server to be ready, and reads in flight.
    private var pendingUsage: [UsageCompletion] = []
    private var usageRequests: [Int: UsageCompletion] = [:]
    private var hasUsageWork: Bool { !pendingUsage.isEmpty || !usageRequests.isEmpty }
    private var serial = 1
    private var ready = false
    private var lastResponse = Date()
    private var launchedAt = Date()
    private let receive: @Sendable (AgentEvent) -> Void

    init(receive: @escaping @Sendable (AgentEvent) -> Void) { self.receive = receive }

    static func runHeadlessCheck() -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        guard let session = environment["DELAY_NO_MORE_CHECK_SESSION"],
              let turn = environment["DELAY_NO_MORE_CHECK_TURN"] else {
            print("Provide the session and turn identifiers for a metadata-only check.")
            return 1
        }
        let delivered = DispatchSemaphore(value: 0)
        let monitor = CodexTurnMonitor { event in
            print("Matched terminal metadata: \(event.status ?? "unknown")")
            delivered.signal()
        }
        monitor.track(session: session, turn: turn)
        let success = delivered.wait(timeout: .now() + 12) == .success
        monitor.stop()
        if !success { print("No matching terminal metadata became available.") }
        return success ? 0 : 1
    }

    func track(session: String, turn: String) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.tracked[session]?.turn != turn { self.tracked[session] = Tracked(turn: turn) }
            if self.process == nil { self.launch() }
        }
    }

    /// Observe exactly these session → turn pairs. Unchanged pairs keep their
    /// backoff; anything no longer active stops being polled.
    func sync(_ turns: [String: String]) {
        queue.async { [weak self] in
            guard let self else { return }
            for session in Array(self.tracked.keys) where turns[session] != self.tracked[session]?.turn {
                self.tracked.removeValue(forKey: session)
            }
            for (session, turn) in turns where self.tracked[session] == nil {
                self.tracked[session] = Tracked(turn: turn)
            }
            if !self.tracked.isEmpty, self.process == nil { self.launch() }
        }
    }

    /// Reads the weekly usage window once. The server is launched if needed and
    /// stops again afterwards unless turns are being observed.
    func requestRateLimits(completion: @escaping UsageCompletion) {
        queue.async { [weak self] in
            guard let self else { completion(nil); return }
            self.pendingUsage.append(completion)
            if self.process == nil { self.launch() } else if self.ready { self.flushUsage() }
        }
    }

    private func flushUsage() {
        let waiting = pendingUsage
        pendingUsage = []
        for completion in waiting {
            serial += 1
            usageRequests[serial] = completion
            write(["id": serial, "method": "account/rateLimits/read"])
        }
    }

    private func failUsage() {
        let all = pendingUsage + Array(usageRequests.values)
        pendingUsage = []; usageRequests = [:]
        for completion in all { completion(nil) }
    }

    /// 3 s for the first two minutes, then 10 s, then 30 s.
    static func pollInterval(age: TimeInterval) -> TimeInterval {
        age < 120 ? 3 : age < 600 ? 10 : 30
    }

    func stop() {
        queue.sync {
            timer?.cancel(); timer = nil
            shutdown()
            tracked = [:]
        }
    }

    private func launch() {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { failUsage(); return }
        let process = Process()
        let incoming = Pipe(), outgoing = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = incoming
        process.standardOutput = outgoing
        process.standardError = FileHandle.nullDevice
        // An isolated protocol client; no inherited hook callback or model turn.
        process.environment = ProcessInfo.processInfo.environment
        let handle = outgoing.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            self?.queue.async { [weak self] in self?.consume(bytes) }
        }
        do {
            try process.run()
            lastResponse = Date()
            launchedAt = Date()
            self.process = process
            input = incoming.fileHandleForWriting
            output = handle
            write(["id": 1, "method": "initialize", "params": [
                "clientInfo": ["name": "delay_no_more_status", "version": "1.10.0"],
                "capabilities": ["experimentalApi": true]
            ]])
            if timer == nil {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(250))
                timer.setEventHandler { [weak self] in self?.poll() }
                self.timer = timer
                timer.resume()
            }
        } catch { handle.readabilityHandler = nil; failUsage() }
    }

    private func poll() {
        guard !tracked.isEmpty || hasUsageWork else { shutdown(); timer?.cancel(); timer = nil; return }
        guard process?.isRunning == true else { shutdown(); if !tracked.isEmpty { launch() }; return }
        if (!ready || !requests.isEmpty || !usageRequests.isEmpty) && Date().timeIntervalSince(lastResponse) > 10 {
            shutdown()
            return
        }
        guard ready else { return }
        let now = Date()
        // The app-server's memory grows while it serves queries; recycle it.
        if requests.isEmpty, !hasUsageWork, now.timeIntervalSince(launchedAt) > 900 { shutdown(); return }
        // Bounded observation: at most 24 hours per observed turn. Timeout has no outcome.
        for session in Array(tracked.keys) {
            guard var value = tracked[session] else { continue }
            let age = now.timeIntervalSince(value.started)
            if age > 86_400 { tracked.removeValue(forKey: session); continue }
            if value.nextPoll > now || requests.values.contains(where: { $0.0 == session }) { continue }
            value.nextPoll = now.addingTimeInterval(Self.pollInterval(age: age))
            tracked[session] = value
            serial += 1
            requests[serial] = (session, value.turn)
            write(["id": serial, "method": "thread/turns/list", "params": [
                "threadId": session, "limit": 1, "sortDirection": "desc", "itemsView": "notLoaded"
            ]])
        }
    }

    private func write(_ value: [String: Any]) {
        guard let input, var data = try? JSONSerialization.data(withJSONObject: value) else { return }
        data.append(0x0a)
        do { try input.write(contentsOf: data) } catch { shutdown() }
    }

    private func consume(_ bytes: Data) {
        guard !bytes.isEmpty else { shutdown(); return }
        buffer.append(bytes)
        guard buffer.count <= 1_048_576 else { shutdown(); return }
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = message["id"] as? Int else { continue }
            lastResponse = Date()
            if id == 1 {
                guard message["result"] != nil else { shutdown(); return }
                ready = true
                write(["method": "initialized"])
                flushUsage()
                continue
            }
            if let completion = usageRequests.removeValue(forKey: id) {
                // Only the weekly window's percent and reset time are kept.
                completion((message["result"] as? [String: Any]).flatMap { AgentUsage.fromCodexRateLimits($0) })
                continue
            }
            guard let (session, turn) = requests.removeValue(forKey: id), tracked[session]?.turn == turn else { continue }
            if let event = Self.terminalEvent(from: message, session: session, turn: turn) {
                tracked.removeValue(forKey: session)
                receive(event)
            }
            // No raw result, error text, turn item or message is retained.
        }
    }

    static func terminalEvent(from message: [String: Any], session: String, turn: String) -> AgentEvent? {
        guard let result = message["result"] as? [String: Any],
              let turns = result["data"] as? [[String: Any]], let first = turns.first,
              first["id"] as? String == turn,
              let status = first["status"] as? String,
              ["completed", "failed", "interrupted"].contains(status),
              (first["items"] as? [Any])?.isEmpty != false else { return nil }
        return AgentEvent(eventID: "terminal:\(session):\(turn):\(status)", sessionID: session,
                              turnID: turn, event: "TurnCompleted", status: status)
    }

    private func shutdown() {
        output?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        output = nil; input = nil
        if process?.isRunning == true { process?.terminate() }; process = nil
        ready = false; buffer = Data(); requests = [:]
        failUsage()
    }
    deinit { timer?.cancel(); shutdown() }
}
