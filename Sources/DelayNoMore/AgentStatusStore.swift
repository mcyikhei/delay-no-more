import Combine
import Darwin
import DelayCore
import Foundation

/// Local datagrams are deliberately independent of Codex's approval channel.
final class AgentStatusListener {
    private var source: DispatchSourceRead?
    private var ownsSocket = false
    private let url: URL

    init(url: URL) { self.url = url }

    func start(receive: @escaping @Sendable (AgentEvent) -> Void) throws {
        guard source == nil else { return }
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(url.path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw NSError(domain: "Agent connection", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The local connection path is too long."])
        }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            bytes.withUnsafeBytes { target.copyBytes(from: $0) }
        }
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFSOCK && info.st_uid == getuid() else {
                throw NSError(domain: "Agent connection", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "The connection path is occupied by another file."])
            }
            guard unlink(url.path) == 0 else { throw posixError() }
        }
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw posixError() }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { let error = posixError(); close(descriptor); throw error }
        ownsSocket = true
        guard chmod(url.path, 0o600) == 0 else {
            let error = posixError(); close(descriptor); unlink(url.path); ownsSocket = false; throw error
        }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: DispatchQueue(label: "com.delaynomore.agent-events"))
        source.setEventHandler {
            // Bound each dispatch so an event flood cannot monopolise the queue.
            for _ in 0..<64 {
                var buffer = [UInt8](repeating: 0, count: 4097)
                let count = recv(descriptor, &buffer, buffer.count, 0)
                guard count > 0 else { break }
                guard count <= 4096,
                      let event = try? JSONDecoder().decode(AgentEvent.self, from: Data(buffer.prefix(count))),
                      event.isValid(at: Date()) else { continue }
                receive(event)
            }
        }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel(); source = nil
        if ownsSocket { unlink(url.path); ownsSocket = false }
    }

    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    deinit { stop() }
}

@MainActor
final class AgentStatusStore: ObservableObject {
    @Published private(set) var snapshot = AgentStatusSnapshot()
    @Published private(set) var connectionError: String?
    private var reducer = AgentStatusReducer()
    private var preview = AgentStatusPreview()
    private var listener: AgentStatusListener?
    private var generation = UUID()
    private var turnMonitor: CodexTurnMonitor?
    private var cueTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var livenessTask: Task<Void, Never>?
    private let log = StatusLog()

    func start() {
        stop()
        guard AgentHookBridge.anyInstalled else { return }
        do {
            let generation = self.generation
            let log = self.log
            turnMonitor = CodexTurnMonitor { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation, let turn = event.turnID else { return }
                    let matched = self.reducer.isTracking(agent: .codex, session: event.sessionID, turn: turn)
                    log.record(event, note: "monitor matched=\(matched)")
                    guard matched else { return }
                    self.apply(event)
                }
            }
            let listener = AgentStatusListener(url: AgentHookBridge.socketURL)
            try listener.start { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.receive(event)
                }
            }
            self.listener = listener
            connectionError = nil
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private func receive(_ event: AgentEvent) {
        if event.event == "Preview" {
            preview.apply(event)
            log.record(event, note: "preview \(event.status ?? "-")")
            schedulePreviewEnd()
            publish()
            return
        }
        apply(event)
    }

    private func apply(_ event: AgentEvent) {
        let before = reducer.snapshot.activity
        reducer.receive(event)
        log.record(event, note: "\(before.rawValue)->\(reducer.snapshot.activity.rawValue)")
        afterReduce()
    }

    /// Every reduce re-derives which Codex turns need stored outcomes, so a
    /// turn learned from an earlier event is never left unobserved.
    private func afterReduce() {
        turnMonitor?.sync(reducer.activeCodexTurns())
        scheduleCueRefresh()
        scheduleLivenessChecks()
        publish()
    }

    private func publish() {
        let next = preview.overlay(reducer.snapshot)
        if next != snapshot { snapshot = next }
    }

    /// Replaces a forever 1 s loop: the reducer only time-expires its 3 s cue.
    private func scheduleCueRefresh() {
        cueTask?.cancel(); cueTask = nil
        guard reducer.snapshot.cueDate != nil else { return }
        cueTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 3_050_000_000) } catch { return }
            guard let self else { return }
            self.reducer.refresh()
            self.publish()
        }
    }

    private func schedulePreviewEnd() {
        previewTask?.cancel(); previewTask = nil
        guard let expires = preview.expires, preview.isActive() else { return }
        previewTask = Task { [weak self] in
            let delay = max(0, expires.timeIntervalSinceNow) + 0.05
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            self?.publish()
        }
    }

    /// While a session is active, check every 30 s that its agent process
    /// still exists. A closed terminal or crashed agent can never finish.
    private func scheduleLivenessChecks() {
        guard livenessTask == nil, reducer.hasActiveOwnedSessions else { return }
        livenessTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard let self else { return }
                if self.reducer.pruneDeadOwners(isAlive: { kill($0, 0) == 0 || errno == EPERM }) {
                    self.log.note("removed session(s) whose agent process exited")
                    self.afterReduce()
                }
                if !self.reducer.hasActiveOwnedSessions { self.livenessTask = nil; return }
            }
        }
    }

    func acknowledgeCompletion() {
        guard snapshot.activity == .finished else { return }
        preview.acknowledgeCompletion()
        reducer.acknowledgeCompletion()
        publish()
    }

    func stop() {
        generation = UUID()
        turnMonitor?.stop(); turnMonitor = nil
        cueTask?.cancel(); cueTask = nil
        previewTask?.cancel(); previewTask = nil
        livenessTask?.cancel(); livenessTask = nil
        listener?.stop(); listener = nil
        preview = AgentStatusPreview()
        reducer.disconnect(); publish()
    }
}

/// Minimal status trail for diagnosing stuck colors. Records agent, event,
/// hashed IDs and state transitions only — never prompts, payloads or tasks.
final class StatusLog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.delaynomore.status-log")
    private let url: URL
    private let limit = 256 * 1024

    init() {
        url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DelayNoMore/status.log")
    }

    static func shortHash(_ value: String?) -> String {
        guard let value else { return "-" }
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(format: "%08x", hash)
    }

    func record(_ event: AgentEvent, note: String) {
        let status = event.status.map { "(\($0))" } ?? ""
        write("\(event.agent.rawValue) \(event.event)\(status) s=\(Self.shortHash(event.sessionID)) t=\(Self.shortHash(event.turnID)) \(note)")
    }

    func note(_ text: String) { write(text) }

    private func write(_ text: String) {
        let line = ISO8601DateFormatter().string(from: Date()) + " " + text + "\n"
        queue.async { [url, limit] in
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int, size > limit {
                let old = url.appendingPathExtension("1")
                try? manager.removeItem(at: old)
                try? manager.moveItem(at: url, to: old)
            }
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
