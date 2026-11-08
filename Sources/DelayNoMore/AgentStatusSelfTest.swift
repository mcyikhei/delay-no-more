import Darwin
import DelayCore
import Foundation

/// Runs without NSApplication, an open window, Codex or access to real hooks.
enum AgentStatusSelfTest {
    private final class Received: @unchecked Sendable {
        let lock = NSLock()
        var events: [CodexHookEvent] = []
        func append(_ event: CodexHookEvent) { lock.lock(); events.append(event); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    }

    static func run(check: (Bool, String) -> Void) {
        runAgentChecks(check: check)
        let now = Date()
        func event(_ session: String, _ kind: String, _ turn: String? = "turn", _ seconds: Double = 0,
                   status: String? = nil, id: String = UUID().uuidString) -> CodexHookEvent {
            CodexHookEvent(eventID: id, sessionID: session, turnID: turn, event: kind,
                           time: now.timeIntervalSince1970 + seconds, status: status)
        }
        func at(_ seconds: Double) -> Date { now.addingTimeInterval(seconds) }

        var reducer = CodexStatusReducer()
        check(reducer.snapshot.activity == .unknown, "status starts uncertain")
        let first = event("one", "UserPromptSubmit")
        reducer.receive(first, at: now)
        reducer.receive(first, at: now)
        reducer.receive(event("one", "Stop", "turn", 1, id: first.eventID), at: at(1))
        check(reducer.snapshot.activity == .working && reducer.snapshot.activeCount == 1,
              "duplicate event IDs cannot repeat or change activity")
        let beforeInvalid = reducer.snapshot
        reducer.receive(AgentEvent(schema: 9, sessionID: "bad", event: "Stop", time: now.timeIntervalSince1970), at: now)
        reducer.receive(event("bad", "UnknownEvent"), at: now)
        reducer.receive(event("bad", "ThreadStatus", status: "unrecognized"), at: now)
        reducer.receive(event("one", "Stop"), at: at(31))
        check(reducer.snapshot == beforeInvalid, "malformed, unknown, and expired events cannot alter status")
        reducer.receive(event("one", "TurnStarted", "new", 4), at: at(4))
        reducer.receive(event("one", "PermissionRequest", "new", 3), at: at(4))
        reducer.receive(event("one", "Stop", "turn", 5), at: at(5))
        reducer.receive(event("one", "TurnCompleted", "turn", 6, status: "completed"), at: at(6))
        check(reducer.snapshot.activity == .working, "older timestamps and terminal events from an old turn cannot overwrite current work")
        reducer.receive(event("one", "SessionStart", "new", 7), at: at(7))
        check(reducer.snapshot.activity == .working, "resume or compaction cannot erase known activity")

        var aggregate = CodexStatusReducer()
        aggregate.receive(event("unobserved", "SessionStart"), at: now)
        aggregate.receive(event("a", "TurnStarted"), at: now)
        aggregate.receive(event("b", "TurnStarted"), at: now)
        check(aggregate.snapshot.activity == .working && aggregate.snapshot.activeCount == 2,
              "observed work takes priority over an unobserved session")
        aggregate.receive(event("a", "PermissionRequest", "turn", 1), at: at(1))
        check(aggregate.snapshot.activity == .waiting && aggregate.snapshot.activeCount == 2,
              "a pending approval takes aggregate priority over other work")
        aggregate.acknowledgeCompletion(at: at(1))
        check(aggregate.snapshot.activity == .waiting, "hover cannot acknowledge a pending approval")
        aggregate.receive(event("a", "PreToolUse", "turn", 2), at: at(2))
        check(aggregate.snapshot.activity == .working, "tool activity clears the session's pending approval")
        aggregate.receive(event("a", "DecisionRequest", "turn", 3), at: at(3))
        check(aggregate.snapshot.activity == .waiting, "an explicit decision request enters waiting")
        aggregate.receive(event("a", "PostToolUse", "turn", 4), at: at(4))
        aggregate.receive(event("b", "Stop", "turn", 5), at: at(5))
        check(aggregate.snapshot.activity == .working && aggregate.snapshot.cue == nil && aggregate.snapshot.activeCount == 2,
              "a root Stop preserves both unresolved active turns")
        aggregate.receive(event("a", "TurnCompleted", "turn", 6, status: "failed"), at: at(6))
        check(aggregate.snapshot.activity == .working, "another unresolved root keeps working after one explicit failure")
        aggregate.receive(event("b", "TurnCompleted", "turn", 7, status: "completed"), at: at(7))
        check(aggregate.snapshot.activity == .failed, "failure becomes visible after every active root has an explicit outcome")
        aggregate.acknowledgeCompletion(at: at(7))
        aggregate.refresh(at: at(600))
        check(aggregate.snapshot.activity == .failed, "failure remains latched and hover cannot acknowledge it")
        aggregate.receive(event("a", "Stop", "turn", 601), at: at(601))
        check(aggregate.snapshot.activity == .failed, "a generic Stop cannot clear an explicit failure")
        aggregate.receive(event("next", "TurnStarted", "next-turn", 602), at: at(602))
        check(aggregate.snapshot.activity == .working, "a new cycle clears the previous terminal failure")
        aggregate.acknowledgeCompletion(at: at(602))
        check(aggregate.snapshot.activity == .working, "hover cannot acknowledge active work")

        var completed = CodexStatusReducer()
        completed.receive(event("done", "TurnStarted"), at: now)
        let completion = event("done", "TurnCompleted", "turn", 1, status: "completed")
        completed.receive(completion, at: at(1))
        check(completed.snapshot.activity == .finished, "only explicit successful completion enters finished")
        completed.receive(event("done", "PostToolUse", "turn", 2), at: at(2))
        check(completed.snapshot.activity == .finished, "late tool activity cannot erase a confirmed terminal outcome")
        completed.refresh(at: at(1000))
        check(completed.snapshot.activity == .finished, "finished state stays latched without a timer expiry")
        completed.acknowledgeCompletion(at: at(1000))
        check(completed.snapshot.activity == .idle, "hover acknowledges a finished state")
        completed.receive(completion, at: at(1))
        check(completed.snapshot.activity == .idle, "duplicate completion cannot relatch an acknowledged result")
        completed.receive(event("done", "TurnStarted", "next", 1001), at: at(1001))
        completed.receive(event("done", "TurnCompleted", "next", 1002, status: "completed"), at: at(1002))
        check(completed.snapshot.activity == .finished, "a later completion relatches after acknowledgement")

        var concurrent = CodexStatusReducer()
        concurrent.receive(event("a", "TurnStarted"), at: now)
        concurrent.receive(event("b", "TurnStarted"), at: now)
        concurrent.receive(event("a", "TurnCompleted", "turn", 1, status: "failed"), at: at(1))
        check(concurrent.snapshot.activity == .working, "remaining active work takes priority over a completed failure")
        concurrent.receive(event("b", "TurnCompleted", "turn", 2, status: "completed"), at: at(2))
        check(concurrent.snapshot.activity == .failed, "failure takes priority when all roots have stopped")

        var interrupted = CodexStatusReducer()
        interrupted.receive(event("one", "TurnStarted"), at: now)
        interrupted.receive(event("one", "Interrupt", "turn", 1), at: at(1))
        check(interrupted.snapshot.activity == .idle && interrupted.snapshot.cue == .interrupted,
              "interruption stays neutral and never signals successful completion")
        interrupted.receive(event("one", "PreToolUse", "turn", 2), at: at(2))
        check(interrupted.snapshot.activity == .working && interrupted.snapshot.cue == nil,
              "continuation after interruption supersedes its cue")
        interrupted.receive(event("one", "Stop", "turn", 3), at: at(3))
        check(interrupted.snapshot.activity == .working && interrupted.snapshot.cue == nil,
              "generic Stop preserves working while metadata is pending")
        interrupted.receive(event("one", "PostToolUse", "turn", 4), at: at(4))
        check(interrupted.snapshot.activity == .working, "tool continuation can resume after Stop")
        interrupted.refresh(at: at(310))
        check(interrupted.snapshot.activity == .working && interrupted.snapshot.activeCount == 1,
              "silent active turns remain working without an expiry timer")
        interrupted.receive(event("one", "SessionEnd", "turn", 311), at: at(311))
        check(interrupted.snapshot.activity == .working && interrupted.snapshot.activeCount == 1,
              "SessionEnd preserves active work until its metadata outcome")
        interrupted.disconnect()
        check(interrupted.snapshot == CodexStatusSnapshot(), "disconnect clears transient status")

        var continuous = CodexStatusReducer()
        var continuousStates: [CodexActivity] = []
        continuous.receive(event("one", "TurnStarted"), at: now)
        continuousStates.append(continuous.snapshot.activity)
        continuous.receive(event("one", "Stop", "turn", 1), at: at(1))
        continuousStates.append(continuous.snapshot.activity)
        continuous.receive(event("one", "SessionEnd", "turn", 2), at: at(2))
        continuousStates.append(continuous.snapshot.activity)
        continuous.refresh(at: at(86_400))
        continuousStates.append(continuous.snapshot.activity)
        continuous.receive(event("one", "TurnCompleted", "turn", 86_401, status: "completed"), at: at(86_401))
        continuousStates.append(continuous.snapshot.activity)
        check(continuousStates == [.working, .working, .working, .working, .finished],
              "working transitions directly to finished after Stop, SessionEnd, and a full day of silence")
        continuous.acknowledgeCompletion(at: at(86_402))
        check(continuous.snapshot.activity == .idle, "hover still acknowledges the directly completed turn")

        var missingTurn = CodexStatusReducer()
        missingTurn.receive(event("one", "TurnStarted", "known-turn"), at: now)
        missingTurn.receive(event("one", "Stop", nil, 1), at: at(1))
        missingTurn.receive(event("one", "SessionEnd", nil, 2), at: at(2))
        missingTurn.refresh(at: at(86_400))
        check(missingTurn.snapshot.activity == .working && missingTurn.isTracking(session: "one", turn: "known-turn"),
              "hooks without turn IDs preserve the known unresolved turn")
        missingTurn.receive(event("one", "TurnCompleted", "known-turn", 86_401, status: "completed"), at: at(86_401))
        check(missingTurn.snapshot.activity == .finished, "matching metadata still completes a turn after ID-less SessionEnd")

        var newUnidentifiedTurn = CodexStatusReducer()
        newUnidentifiedTurn.receive(event("one", "TurnStarted", "old-turn"), at: now)
        newUnidentifiedTurn.receive(event("one", "UserPromptSubmit", nil, 1), at: at(1))
        newUnidentifiedTurn.receive(event("one", "TurnCompleted", "old-turn", 2, status: "completed"), at: at(2))
        check(newUnidentifiedTurn.snapshot.activity == .working && !newUnidentifiedTurn.isTracking(session: "one", turn: "old-turn"),
              "an ID-less new prompt invalidates the previous turn's delayed outcome")
        newUnidentifiedTurn.receive(event("one", "PreToolUse", "fresh-turn", 3), at: at(3))
        newUnidentifiedTurn.receive(event("one", "TurnCompleted", "old-turn", 4, status: "failed"), at: at(4))
        check(newUnidentifiedTurn.snapshot.activity == .working && newUnidentifiedTurn.isTracking(session: "one", turn: "fresh-turn"),
              "new activity establishes the fresh turn without accepting an old completion")
        newUnidentifiedTurn.receive(event("one", "TurnCompleted", "fresh-turn", 5, status: "completed"), at: at(5))
        check(newUnidentifiedTurn.snapshot.activity == .finished, "the fresh turn can complete directly after its ID is observed")

        var waiting = CodexStatusReducer()
        waiting.receive(event("approval", "TurnStarted"), at: now)
        waiting.receive(event("approval", "PermissionRequest", "turn", 1), at: at(1))
        waiting.receive(event("approval", "Stop", "turn", 2), at: at(2))
        waiting.receive(event("approval", "SessionEnd", "turn", 3), at: at(3))
        waiting.refresh(at: at(86_400))
        check(waiting.snapshot.activity == .waiting && waiting.snapshot.activeCount == 1,
              "waiting remains latched through Stop, SessionEnd, and silence")
        waiting.receive(event("approval", "PreToolUse", "turn", 86_401), at: at(86_401))
        check(waiting.snapshot.activity == .working, "real resumed activity clears ordinary approval waiting")

        var asyncDecision = CodexStatusReducer()
        asyncDecision.receive(event("one", "UserPromptSubmit"), at: now)
        asyncDecision.receive(event("one", "DecisionRequestAsync", "turn", 1), at: at(1))
        asyncDecision.receive(event("one", "PostToolUse", "turn", 2), at: at(2))
        check(asyncDecision.snapshot.activity == .waiting, "asynchronous decision remains pending after immediate tool return")
        asyncDecision.receive(event("one", "PreModelRequest", "turn", 3), at: at(3))
        check(asyncDecision.snapshot.activity == .waiting, "independent model work does not clear an asynchronous question")
        asyncDecision.receive(event("one", "SessionEnd", "turn", 4), at: at(4))
        asyncDecision.refresh(at: at(1000))
        asyncDecision.receive(event("one", "PreModelRequest", "turn", 1001), at: at(1001))
        check(asyncDecision.snapshot.activity == .waiting, "SessionEnd and silence cannot clear a pending asynchronous question")
        asyncDecision.receive(event("one", "UserPromptSubmit", "answer", 1002), at: at(1002))
        check(asyncDecision.snapshot.activity == .working, "new user input clears the pending asynchronous decision")
        asyncDecision.receive(event("one", "PreToolUse", "old", 1003), at: at(1003))
        check(!asyncDecision.isTracking(session: "one", turn: "old"), "rejected subagent or old turn cannot replace metadata tracking")
        for name in ["functions.request_user_input", "functions.request_user_input_async"] {
            let input: [String: Any] = ["session_id": "one", "turn_id": "turn", "hook_event_name": "PreToolUse", "tool_name": name]
            let projected = try? JSONSerialization.data(withJSONObject: input)
            let actual = projected.flatMap { AgentHookBridge.filteredEvent(agent: .codex, from: $0) }
            check(actual?.event == (name.hasSuffix("_async") ? "DecisionRequestAsync" : "DecisionRequest"),
                  "decision tool is projected without request contents")
        }

        func turnResponse(_ status: String, id: String = "observed-turn", items: [Any]? = nil) -> [String: Any] {
            var turn: [String: Any] = ["id": id, "status": status]
            if let items { turn["items"] = items }
            return ["result": ["data": [turn]]]
        }
        for status in ["completed", "failed", "interrupted"] {
            let terminal = CodexTurnMonitor.terminalEvent(from: turnResponse(status),
                                                         session: "observed-chat", turn: "observed-turn")
            check(terminal?.event == "TurnCompleted" && terminal?.status == status
                  && terminal?.sessionID == "observed-chat" && terminal?.turnID == "observed-turn",
                  "turn metadata projects the matching \(status) outcome")
        }
        check(CodexTurnMonitor.terminalEvent(from: turnResponse("completed", id: "old-turn"),
                                            session: "observed-chat", turn: "observed-turn") == nil,
              "an older turn result cannot finish the tracked turn")
        check(CodexTurnMonitor.terminalEvent(from: turnResponse("inProgress"),
                                            session: "observed-chat", turn: "observed-turn") == nil,
              "in-progress turn metadata cannot infer completion")
        check(CodexTurnMonitor.terminalEvent(from: turnResponse("completed", items: [["text": "PRIVATE"]]),
                                            session: "observed-chat", turn: "observed-turn") == nil,
              "a result containing turn items is rejected")
        check(CodexTurnMonitor.terminalEvent(from: ["error": ["message": "PRIVATE"]],
                                            session: "observed-chat", turn: "observed-turn") == nil,
              "a protocol error cannot become a failed turn event")
        let privateResponse: [String: Any] = [
            "result": ["data": [["id": "observed-turn", "status": "failed", "items": [],
                                  "prompt": "PRIVATE", "error": ["message": "PRIVATE"]]]],
            "prompt": "PRIVATE", "error": ["message": "PRIVATE"]
        ]
        if let projected = CodexTurnMonitor.terminalEvent(from: privateResponse,
                                                          session: "observed-chat", turn: "observed-turn"),
           let bytes = try? JSONEncoder().encode(projected),
           let text = String(data: bytes, encoding: .utf8),
           let fields = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            let allowed = Set(["schema", "agent", "eventID", "sessionID", "turnID", "event", "time", "status", "pid"])
            check(projected.status == "failed" && !text.contains("PRIVATE") && Set(fields.keys).isSubset(of: allowed),
                  "terminal projection retains only allow-listed metadata and discards prompt and error text")
        } else {
            check(false, "terminal metadata projection fixture")
        }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dnm-hook-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("hooks.json")
            let original = Data(#"{"custom":"keep","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo existing"}]}]}}"#.utf8)
            try original.write(to: url)
            let executable = directory.appendingPathComponent("a 'quoted' app/DelayNoMore")
            try AgentHookBridge.install(.codex, executable: executable, configURL: url)
            check(AgentHookBridge.isInstalled(.codex, at: url), "hook setup installs all owned events")
            let firstInstall = try Data(contentsOf: url)
            try AgentHookBridge.install(.codex, executable: executable, configURL: url)
            check(try Data(contentsOf: url) == firstInstall, "repeated hook setup is idempotent")
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix("backup.json") }
            check(backups.count == 1 && (try? Data(contentsOf: backups[0])) == original,
                  "hook setup preserves exact original configuration backup")
            try AgentHookBridge.uninstall(.codex, configURL: url)
            let uninstalled = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            let stop = ((uninstalled["hooks"] as! [String: Any])["Stop"] as! [[String: Any]])[0]
            check(uninstalled["custom"] as? String == "keep"
                  && (stop["hooks"] as! [[String: Any]])[0]["command"] as? String == "echo existing"
                  && !AgentHookBridge.isInstalled(.codex, at: url), "disconnect removes only owned hooks")
            let invalid = Data("{corrupt".utf8)
            try invalid.write(to: url)
            var rejected = false
            do { try AgentHookBridge.install(.codex, executable: executable, configURL: url) } catch { rejected = true }
            check(rejected && (try? Data(contentsOf: url)) == invalid, "unreadable hook configuration remains untouched")
            let full = Data(#"{"session_id":"s","turn_id":"t","hook_event_name":"UserPromptSubmit","prompt":"PRIVATE","last_assistant_message":"PRIVATE","tool_input":{"secret":"PRIVATE"}}"#.utf8)
            if let filtered = AgentHookBridge.filteredEvent(agent: .codex, from: full),
               let encoded = try? JSONEncoder().encode(filtered), let text = String(data: encoded, encoding: .utf8) {
                check(!text.contains("PRIVATE") && !text.contains("prompt") && !text.contains("tool_input"),
                      "hook projection strips all prompt, reply and tool content")
            } else { check(false, "valid hook metadata projection") }
        } catch { check(false, "hook setup fixtures: \(error.localizedDescription)") }

        let socketPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dnm-\(UUID().uuidString.prefix(8)).sock")
        do {
            try Data("preserve".utf8).write(to: socketPath)
            var failedListener: AgentStatusListener? = AgentStatusListener(url: socketPath)
            var rejected = false
            do { try failedListener?.start { _ in }; } catch { rejected = true }
            failedListener = nil
            check(rejected && (try? Data(contentsOf: socketPath)) == Data("preserve".utf8),
                  "occupied socket path survives failed start and listener destruction")
            try FileManager.default.removeItem(at: socketPath)
        } catch { check(false, "occupied socket fixture") }
        let listener = AgentStatusListener(url: socketPath)
        let received = Received()
        let delivered = DispatchSemaphore(value: 0)
        do {
            try listener.start { value in received.append(value); delivered.signal() }
            defer { listener.stop() }
            let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
            guard descriptor >= 0 else { check(false, "test sender socket"); return }
            defer { close(descriptor) }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                Array(socketPath.path.utf8CString).withUnsafeBytes { destination.copyBytes(from: $0) }
            }
            func send(_ data: Data) {
                data.withUnsafeBytes { buffer in
                    withUnsafePointer(to: &address) { pointer in
                        _ = pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(descriptor, buffer.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                        }
                    }
                }
            }
            send(Data("malformed".utf8))
            send(try JSONEncoder().encode(first))
            check(delivered.wait(timeout: .now() + 1) == .success && received.count == 1,
                  "local datagram listener rejects malformed payload and accepts metadata")
            let attributes = try FileManager.default.attributesOfItem(atPath: socketPath.path)
            check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "status socket is private to current user")
        } catch { check(false, "local status socket: \(error.localizedDescription)") }
    }

    /// 1.9: Claude Code policy, shared aggregation, monitor sync, liveness,
    /// preview isolation, Claude settings merge and the energy schedule.
    static func runAgentChecks(check: (Bool, String) -> Void) {
        let now = Date()
        func at(_ seconds: Double) -> Date { now.addingTimeInterval(seconds) }
        func claude(_ session: String, _ kind: String, _ seconds: Double = 0, pid: Int32? = nil) -> AgentEvent {
            AgentEvent(agent: .claude, sessionID: session, event: kind,
                       time: now.timeIntervalSince1970 + seconds, pid: pid)
        }
        func codex(_ session: String, _ kind: String, _ turn: String? = "turn", _ seconds: Double = 0,
                   status: String? = nil, pid: Int32? = nil) -> AgentEvent {
            AgentEvent(agent: .codex, sessionID: session, turnID: turn, event: kind,
                       time: now.timeIntervalSince1970 + seconds, status: status, pid: pid)
        }

        // Claude Code turn lifecycle.
        var turn = AgentStatusReducer()
        var states: [AgentActivity] = []
        for (index, kind) in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"].enumerated() {
            turn.receive(claude("c", kind, Double(index)), at: at(Double(index)))
            states.append(turn.snapshot.activity)
        }
        check(states == [.working, .working, .working, .finished], "Claude prompt, tools and Stop go blue to green with no gap")
        turn.receive(claude("c", "IdlePrompt", 70), at: at(70))
        check(turn.snapshot.activity == .finished, "Claude idle prompt cannot erase an unacknowledged green")
        turn.receive(claude("c", "SessionEnd", 71), at: at(71))
        check(turn.snapshot.activity == .finished, "Claude SessionEnd keeps an unacknowledged outcome")
        turn.acknowledgeCompletion(at: at(72))
        check(turn.snapshot.activity == .idle, "hover acknowledges a Claude completion")

        var approval = AgentStatusReducer()
        approval.receive(claude("c", "UserPromptSubmit"), at: now)
        approval.receive(claude("c", "PermissionRequest", 1), at: at(1))
        check(approval.snapshot.activity == .waiting, "Claude permission request turns yellow")
        approval.receive(claude("c", "PostToolUse", 2), at: at(2))
        check(approval.snapshot.activity == .working, "approved Claude tool resumes blue")
        approval.receive(claude("c", "DecisionRequest", 3), at: at(3))
        check(approval.snapshot.activity == .waiting, "Claude question or permission notification turns yellow")
        approval.receive(claude("c", "StopFailure", 4), at: at(4))
        check(approval.snapshot.activity == .failed, "Claude StopFailure turns red")
        approval.receive(claude("c", "UserPromptSubmit", 5), at: at(5))
        check(approval.snapshot.activity == .working, "a new Claude prompt clears the failure")

        var interrupted = AgentStatusReducer()
        interrupted.receive(claude("c", "UserPromptSubmit"), at: now)
        interrupted.receive(claude("c", "PreToolUse", 1), at: at(1))
        interrupted.refresh(at: at(3_600))
        check(interrupted.snapshot.activity == .working, "Claude work stays blue through silence")
        interrupted.receive(claude("c", "IdlePrompt", 2), at: at(2))
        check(interrupted.snapshot.activity == .idle && interrupted.snapshot.cue == .interrupted,
              "an idle prompt after Esc proves the interrupted Claude turn ended")

        var ended = AgentStatusReducer()
        ended.receive(claude("c", "UserPromptSubmit"), at: now)
        ended.receive(claude("c", "SessionEnd", 1), at: at(1))
        check(ended.snapshot.activity == .unknown && ended.snapshot.activeCount == 0, "Claude SessionEnd clears active work")

        var reopened = AgentStatusReducer()
        reopened.receive(claude("c", "UserPromptSubmit"), at: now)
        reopened.receive(claude("c", "Stop", 1), at: at(1))
        reopened.receive(claude("c", "PreToolUse", 2), at: at(2))
        check(reopened.snapshot.activity == .working, "newer Claude tool work after Stop reopens blue")
        reopened.receive(claude("c", "PreToolUse", 1.5), at: at(2))
        reopened.receive(claude("c", "Stop", 3), at: at(3))
        check(reopened.snapshot.activity == .finished, "the follow-up Claude turn finishes normally")

        // Combined status across agents.
        var mixed = AgentStatusReducer()
        mixed.receive(codex("same-id", "TurnStarted"), at: now)
        mixed.receive(claude("same-id", "UserPromptSubmit"), at: now)
        check(mixed.snapshot.activeCount == 2, "identical session IDs from different agents stay separate")
        mixed.receive(claude("same-id", "Stop", 1), at: at(1))
        check(mixed.snapshot.activity == .working, "a finished Claude turn cannot turn green while Codex works")
        mixed.receive(claude("other", "PermissionRequest", 2), at: at(2))
        check(mixed.snapshot.activity == .waiting, "attention from either agent takes priority")
        mixed.receive(codex("same-id", "TurnCompleted", "turn", 3, status: "failed"), at: at(3))
        mixed.receive(claude("other", "Stop", 4), at: at(4))
        check(mixed.snapshot.activity == .failed, "after all work ends, a Codex failure outranks Claude success")

        // Monitor sync: a turn learned earlier is observed even when the
        // latest event carries no turn ID (the 1.8.1 stale-blue path).
        var sync = AgentStatusReducer()
        sync.receive(codex("thread", "PreToolUse", "known"), at: now)
        sync.receive(codex("thread", "ThreadStatus", nil, 1, status: "working"), at: at(1))
        sync.receive(claude("c", "UserPromptSubmit", 1), at: at(1))
        check(sync.activeCodexTurns() == ["thread": "known"], "active Codex turns include an earlier-learned turn and exclude Claude")
        sync.receive(codex("thread", "TurnCompleted", "known", 2, status: "completed"), at: at(2))
        check(sync.activeCodexTurns().isEmpty, "a completed turn stops being observed")

        // A started-but-silent session carries no evidence.
        var silent = AgentStatusReducer()
        silent.receive(claude("done", "UserPromptSubmit"), at: now)
        silent.receive(claude("done", "Stop", 1), at: at(1))
        silent.receive(codex("fresh", "SessionStart", nil, 2), at: at(2))
        check(silent.snapshot.activity == .finished, "an empty new session cannot hide another session's green")
        silent.acknowledgeCompletion(at: at(3))
        check(silent.snapshot.activity == .idle, "an empty new session cannot turn an idle tube sleepy")
        var onlySilent = AgentStatusReducer()
        onlySilent.receive(codex("fresh", "SessionStart", nil), at: now)
        check(onlySilent.snapshot.activity == .unknown, "with only silent sessions the tube stays sleepy")

        // Disconnecting one agent keeps the other's status.
        var both = AgentStatusReducer()
        both.receive(codex("x", "TurnStarted"), at: now)
        both.receive(claude("y", "UserPromptSubmit"), at: now)
        both.receive(claude("y", "PermissionRequest", 1), at: at(1))
        both.forget(agent: .claude, at: at(2))
        check(both.snapshot.activity == .working && both.snapshot.activeCount == 1,
              "forgetting Claude keeps Codex work and drops Claude's yellow")
        both.forget(agent: .codex, at: at(3))
        check(both.snapshot.activity == .unknown, "forgetting every agent leaves no status")

        // Liveness.
        var owned = AgentStatusReducer()
        owned.receive(claude("dead", "UserPromptSubmit", pid: 111), at: now)
        owned.receive(claude("dead", "PreToolUse", 1), at: at(1))
        owned.receive(claude("alive", "UserPromptSubmit", pid: 222), at: now)
        check(owned.hasActiveOwnedSessions, "owned active sessions are tracked for liveness")
        let changed = owned.pruneDeadOwners(isAlive: { $0 == 222 }, at: at(2))
        check(changed && owned.snapshot.activeCount == 1 && owned.snapshot.activity == .working,
              "a session whose agent process exited is removed; live ones stay")
        owned.receive(claude("alive", "Stop", 3), at: at(3))
        check(!owned.pruneDeadOwners(isAlive: { _ in false }, at: at(4)) && owned.snapshot.activity == .finished,
              "liveness never removes a finished outcome")

        // Preview isolation.
        var live = AgentStatusReducer()
        var preview = AgentStatusPreview()
        live.receive(codex("p", "TurnStarted"), at: now)
        let before = live.snapshot
        let previewEvent = AgentEvent(sessionID: "preview", event: "Preview", time: now.timeIntervalSince1970,
                                      status: "failed", duration: 10)
        live.receive(previewEvent, at: now)
        preview.apply(previewEvent, at: now)
        check(live.snapshot == before, "a preview datagram never reaches the reducer")
        check(preview.overlay(live.snapshot, at: at(1)).activity == .failed, "a preview overlays the live status")
        live.receive(codex("p", "TurnCompleted", "turn", 5, status: "completed"), at: at(5))
        check(preview.overlay(live.snapshot, at: at(6)).activity == .failed && live.snapshot.activity == .finished,
              "real completion during a preview updates live state underneath")
        check(preview.overlay(live.snapshot, at: at(11)).activity == .finished, "preview expiry reveals the latest live state")
        preview.apply(AgentEvent(sessionID: "preview", event: "Preview", time: now.timeIntervalSince1970, status: "finished", duration: 30), at: now)
        preview.acknowledgeCompletion()
        check(!preview.isActive(at: at(1)), "hover ends a green preview")
        check(!AgentEvent(sessionID: "preview", event: "Preview", time: now.timeIntervalSince1970, status: "working", duration: 600).isValid(at: now),
              "previews are bounded to 60 seconds")

        // Claude hook projection.
        func project(_ fields: [String: Any]) -> AgentEvent? {
            var input: [String: Any] = ["session_id": "s", "prompt": "PRIVATE", "tool_input": ["x": "PRIVATE"]]
            for (key, value) in fields { input[key] = value }
            return (try? JSONSerialization.data(withJSONObject: input)).flatMap { AgentHookBridge.filteredEvent(agent: .claude, from: $0, pid: 42) }
        }
        check(project(["hook_event_name": "Notification", "notification_type": "permission_prompt", "message": "PRIVATE"])?.event == "DecisionRequest",
              "Claude permission notification projects to a decision request")
        check(project(["hook_event_name": "Notification", "notification_type": "idle_prompt"])?.event == "IdlePrompt",
              "Claude idle notification projects to an idle prompt")
        check(project(["hook_event_name": "Notification", "notification_type": "auth_success"]) == nil,
              "unrelated Claude notifications are dropped")
        check(project(["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion"])?.event == "DecisionRequest",
              "Claude asking the user a question turns yellow")
        check(project(["hook_event_name": "PreToolUse", "tool_name": "Bash", "agent_id": "sub"]) == nil,
              "Claude subagent events are ignored")
        check(project(["hook_event_name": "PermissionDenied"])?.event == "PostToolUse", "a denied Claude tool continues work")
        if let projected = project(["hook_event_name": "Stop", "last_assistant_message": "PRIVATE"]),
           let text = String(data: (try? JSONEncoder().encode(projected)) ?? Data(), encoding: .utf8) {
            check(projected.agent == .claude && projected.pid == 42 && !text.contains("PRIVATE"),
                  "Claude projection keeps agent, owner PID and no content")
        } else { check(false, "Claude Stop projection") }
        let subagentCodex = try? JSONSerialization.data(withJSONObject: ["session_id": "s", "turn_id": "t", "hook_event_name": "PreToolUse", "agent_id": "sub"])
        check(subagentCodex.flatMap { AgentHookBridge.filteredEvent(agent: .codex, from: $0) } == nil,
              "Codex subagent events are ignored")
        let legacy = Data(#"{"schema":1,"eventID":"e","sessionID":"s","turnID":"t","event":"Stop","time":1}"#.utf8)
        check((try? JSONDecoder().decode(AgentEvent.self, from: legacy))?.agent == .codex, "schema 1 datagrams decode as Codex")

        // Claude settings merge.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dnm-claude-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("settings.json")
            let original = Data(#"{"theme":"dark","enabledPlugins":{"a@b":true},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#.utf8)
            try original.write(to: url)
            let executable = directory.appendingPathComponent("Delay No More.app/Contents/MacOS/DelayNoMore")
            try AgentHookBridge.install(.claude, executable: executable, configURL: url)
            check(AgentHookBridge.isInstalled(.claude, at: url) && !AgentHookBridge.isInstalled(.codex, at: url),
                  "Claude hooks install for every event and stay separate from Codex")
            let first = try Data(contentsOf: url)
            try AgentHookBridge.install(.claude, executable: executable, configURL: url)
            check(try Data(contentsOf: url) == first, "repeated Claude hook setup is idempotent")
            let root = try JSONSerialization.jsonObject(with: first) as! [String: Any]
            check(root["theme"] as? String == "dark" && (root["enabledPlugins"] as? [String: Bool])?["a@b"] == true,
                  "Claude settings keep unrelated keys")
            let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("settings.delay-no-more.") }
            check(backups.count == 1, "Claude settings are backed up once before the first change")
            try AgentHookBridge.uninstall(.claude, configURL: url)
            let removed = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            let stop = ((removed["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
            check(stop?.count == 1 && stop?.first?["command"] as? String == "say done" && (removed["hooks"] as? [String: Any])?.count == 1,
                  "removing Claude hooks keeps the user's own hooks and drops empty events")

            let legacyURL = directory.appendingPathComponent("hooks.json")
            try Data(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"'/old/DelayNoMore' --codex-hook --delay-no-more-status-v1"}]}]}}"#.utf8).write(to: legacyURL)
            try AgentHookBridge.install(.codex, executable: executable, configURL: legacyURL)
            let refreshed = try JSONSerialization.jsonObject(with: Data(contentsOf: legacyURL)) as! [String: Any]
            let stopHandlers = ((refreshed["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]).flatMap { $0["hooks"] as! [[String: Any]] }
            check(stopHandlers.count == 1 && (stopHandlers[0]["command"] as? String)?.contains("--agent-hook codex") == true,
                  "reinstalling replaces 1.8 Codex handlers instead of duplicating them")
        } catch { check(false, "Claude settings fixtures: \(error.localizedDescription)") }

        // Still poses: status is shown by a glowing outline, with no animation.
        let poses = AgentActivity.allCasesForPoses.map { TubeStatusAppearance.make(activity: $0, cue: nil) }
        check(TubeStatusAppearance.make(activity: .working, cue: nil).glowColor == StackTheme.codexWorking
              && TubeStatusAppearance.make(activity: .waiting, cue: nil).glowColor == StackTheme.codexWaiting
              && TubeStatusAppearance.make(activity: .failed, cue: nil).glowColor == StackTheme.codexFailed
              && TubeStatusAppearance.make(activity: .finished, cue: nil).glowColor == StackTheme.codexFinished
              && TubeStatusAppearance.make(activity: .idle, cue: nil).glowColor == nil
              && TubeStatusAppearance.make(activity: .unknown, cue: nil).glowColor == nil,
              "each agent state has its own outline glow; idle and unknown stay plain glass")
        check(Set(poses.map { "\($0)" }).count == poses.count, "every agent state has a distinct still pose")
    }
}

private extension AgentActivity {
    static let allCasesForPoses: [AgentActivity] = [.unknown, .idle, .working, .waiting, .failed, .finished]
}
