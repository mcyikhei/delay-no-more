import DelayCore
import Foundation

/// Codex hidden helper threads and early "interrupted" readings
/// (seen live on 9 November 2026: four unsaved helper sessions kept the tube blue).
@MainActor
enum CodexThreadSelfTest {
    static func run(check: (Bool, String) -> Void) {
        let now = Date()
        func at(_ seconds: Double) -> Date { now.addingTimeInterval(seconds) }
        func codex(_ session: String, _ event: String, _ seconds: Double, turn: String? = nil,
                   status: String? = nil, id: String = UUID().uuidString) -> AgentEvent {
            AgentEvent(agent: .codex, eventID: id, sessionID: session, turnID: turn ?? "t-" + session, event: event,
                       time: at(seconds).timeIntervalSince1970, status: status, pid: 77)
        }

        // A hidden helper thread: hooks fire, nothing is stored.
        var hidden = AgentStatusReducer()
        hidden.receive(codex("helper", "UserPromptSubmit", 0), at: at(0))
        hidden.receive(codex("helper", "ThreadUnavailable", 1), at: at(1))
        check(hidden.snapshot.activity == .working, "a thread not yet stopped stays blue while unreadable")
        hidden.receive(codex("helper", "Stop", 2), at: at(2))
        check(hidden.snapshot.activity == .working, "Codex Stop alone still waits for the stored outcome")
        hidden.receive(codex("helper", "ThreadUnavailable", 3), at: at(3))
        check(hidden.snapshot.activity == .unknown && hidden.activeCodexTurns().isEmpty,
              "an unsaved thread is dropped once Codex has said Stop")

        // It never hides a real thread's outcome.
        var mixed = AgentStatusReducer()
        mixed.receive(codex("real", "UserPromptSubmit", 0), at: at(0))
        mixed.receive(codex("helper", "UserPromptSubmit", 0.5), at: at(0.5))
        mixed.receive(codex("helper", "Stop", 1), at: at(1))
        mixed.receive(codex("helper", "ThreadUnavailable", 2), at: at(2))
        mixed.receive(codex("real", "Stop", 3), at: at(3))
        mixed.receive(codex("real", "TurnCompleted", 4, status: "completed"), at: at(4))
        check(mixed.snapshot.activity == .finished, "after a helper is dropped the real thread still turns green")
        mixed.receive(codex("real", "ThreadUnavailable", 5), at: at(5))
        check(mixed.snapshot.activity == .finished, "an unreadable finished thread keeps its outcome")

        // SessionEnd counts as stopped too.
        var ended = AgentStatusReducer()
        ended.receive(codex("helper", "UserPromptSubmit", 0), at: at(0))
        ended.receive(codex("helper", "SessionEnd", 1), at: at(1))
        ended.receive(codex("helper", "ThreadUnavailable", 2), at: at(2))
        check(ended.snapshot.activity == .unknown, "an ended unsaved thread is dropped")

        // A new turn resets the evidence.
        var reopened = AgentStatusReducer()
        reopened.receive(codex("s", "UserPromptSubmit", 0, turn: "t1"), at: at(0))
        reopened.receive(codex("s", "Stop", 1, turn: "t1"), at: at(1))
        reopened.receive(codex("s", "UserPromptSubmit", 2, turn: "t2"), at: at(2))
        reopened.receive(codex("s", "ThreadUnavailable", 3, turn: "t2"), at: at(3))
        check(reopened.snapshot.activity == .working, "a new turn needs its own Stop before an unreadable thread is dropped")

        // Early "interrupted" from a turn still being written.
        var early = AgentStatusReducer()
        early.receive(codex("pick", "UserPromptSubmit", 0), at: at(0))
        early.receive(codex("pick", "TurnCompleted", 1, status: "interrupted", id: "terminal:pick:interrupted"), at: at(1))
        check(early.snapshot.activity == .working, "interrupted before Stop is ignored as a mid-write reading")
        early.receive(codex("pick", "Stop", 2), at: at(2))
        early.receive(codex("pick", "TurnCompleted", 3, status: "completed"), at: at(3))
        check(early.snapshot.activity == .finished, "the finished turn then turns green")

        var esc = AgentStatusReducer()
        esc.receive(codex("esc", "UserPromptSubmit", 0), at: at(0))
        esc.receive(codex("esc", "Stop", 1), at: at(1))
        esc.receive(codex("esc", "TurnCompleted", 2, status: "interrupted"), at: at(2))
        check(esc.snapshot.activity == .idle, "interrupted after Stop is trusted")

        // Monitor response classification.
        check(CodexTurnMonitor.isThreadNotLoaded(["id": 2, "error": ["code": -32600, "message": "thread not loaded: 01a1"]]),
              "the app-server's 'thread not loaded' error is recognised")
        check(!CodexTurnMonitor.isThreadNotLoaded(["id": 2, "error": ["code": -32000, "message": "rate limited"]])
              && !CodexTurnMonitor.isThreadNotLoaded(["id": 2, "result": ["data": []]]),
              "other errors and results are not treated as hidden threads")
    }
}
