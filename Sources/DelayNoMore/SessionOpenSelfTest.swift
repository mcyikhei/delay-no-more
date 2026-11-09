import DelayCore
import Foundation

/// Clicking the tube: which session opens, what it clears, and the safety of
/// everything placed into a link or script.
@MainActor
enum SessionOpenSelfTest {
    static func run(check: (Bool, String) -> Void) {
        let now = Date()
        func at(_ seconds: Double) -> Date { now.addingTimeInterval(seconds) }
        func claude(_ session: String, _ event: String, _ seconds: Double) -> AgentEvent {
            AgentEvent(agent: .claude, sessionID: session, event: event, time: at(seconds).timeIntervalSince1970, pid: 4242)
        }
        func codex(_ session: String, _ event: String, _ seconds: Double, status: String? = nil) -> AgentEvent {
            AgentEvent(agent: .codex, sessionID: session, turnID: "t-" + session, event: event,
                       time: at(seconds).timeIntervalSince1970, status: status)
        }

        // Target: the latest session in the shown colour.
        var reducer = AgentStatusReducer()
        reducer.receive(claude("a", "UserPromptSubmit", 0), at: at(0))
        check(reducer.attentionTarget() == nil, "a click while blue opens nothing")
        reducer.receive(claude("b", "UserPromptSubmit", 1), at: at(1))
        reducer.receive(claude("a", "Stop", 2), at: at(2))
        reducer.receive(claude("b", "Stop", 3), at: at(3))
        check(reducer.snapshot.activity == .finished && reducer.attentionTarget()?.sessionID == "b",
              "green opens the latest finished session")
        check(reducer.attentionTarget()?.pid == 4242, "the target keeps its owner process")

        // Opening clears that session only; the next click opens the next.
        if let first = reducer.attentionTarget() { reducer.markOpened(first, at: at(4)) }
        check(reducer.snapshot.activity == .finished && reducer.attentionTarget()?.sessionID == "a",
              "opening one session keeps green for the other finished session")
        if let second = reducer.attentionTarget() { reducer.markOpened(second, at: at(5)) }
        check(reducer.snapshot.activity == .idle && reducer.attentionTarget() == nil,
              "opening the last finished session returns the tube to idle")

        // Amber wins over green and stays until answered.
        var mixed = AgentStatusReducer()
        mixed.receive(claude("done", "UserPromptSubmit", 0), at: at(0))
        mixed.receive(claude("done", "Stop", 1), at: at(1))
        mixed.receive(claude("ask", "UserPromptSubmit", 2), at: at(2))
        mixed.receive(claude("ask", "PermissionRequest", 3), at: at(3))
        let waiting = mixed.attentionTarget()
        check(mixed.snapshot.activity == .waiting && waiting?.sessionID == "ask",
              "amber opens the waiting session, not the newer-colour-ranked finished one")
        if let waiting { mixed.markOpened(waiting, at: at(4)) }
        check(mixed.snapshot.activity == .waiting, "opening a waiting session leaves it amber until answered")
        mixed.receive(claude("ask", "PostToolUse", 5), at: at(5))
        mixed.receive(claude("ask", "Stop", 6), at: at(6))
        check(mixed.attentionTarget()?.sessionID == "ask", "after answering, green opens the newest finish")

        // Results show while other sessions still work; opening returns to blue.
        var parallel = AgentStatusReducer()
        parallel.receive(claude("A", "UserPromptSubmit", 0), at: at(0))
        parallel.receive(claude("B", "UserPromptSubmit", 1), at: at(1))
        parallel.receive(claude("A", "Stop", 2), at: at(2))
        check(parallel.snapshot.activity == .finished && parallel.attentionTarget()?.sessionID == "A",
              "A finishing turns the tube green while B still works")
        parallel.receive(claude("C", "UserPromptSubmit", 3), at: at(3))
        check(parallel.snapshot.activity == .finished, "a new prompt in another session keeps A's green")
        if let a = parallel.attentionTarget() { parallel.markOpened(a, at: at(4)) }
        check(parallel.snapshot.activity == .working, "opening A returns to blue for the sessions still working")
        parallel.receive(claude("A", "UserPromptSubmit", 5), at: at(5))
        parallel.receive(claude("A", "Stop", 6), at: at(6))
        parallel.receive(claude("A", "UserPromptSubmit", 7), at: at(7))
        check(parallel.snapshot.activity == .working, "a new prompt in A clears A's own result")

        // Red, from Codex.
        var failed = AgentStatusReducer()
        failed.receive(codex("thread_1", "TurnStarted", 0), at: at(0))
        failed.receive(codex("thread_1", "TurnCompleted", 1, status: "failed"), at: at(1))
        let red = failed.attentionTarget()
        check(failed.snapshot.activity == .failed && red?.agent == .codex && red?.sessionID == "thread_1",
              "red opens the failed Codex thread")
        if let red { failed.markOpened(red, at: at(2)) }
        check(failed.snapshot.activity == .idle, "opening a failed session returns the tube to idle")

        // Links and scripts only carry validated values.
        check(SessionLocator.codexThreadURL("019a-thread_ID")?.absoluteString == "codex://threads/019a-thread_ID",
              "Codex threads open by their codex:// link")
        check(["", "a/b", "x\"y", "../z", "a b", String(repeating: "a", count: 200)].allSatisfy { SessionLocator.codexThreadURL($0) == nil },
              "unsafe thread IDs never become links")
        check(SessionLocator.isValidTTY("/dev/ttys001") && !SessionLocator.isValidTTY("/dev/ttys001\" & do shell script \"x")
              && !SessionLocator.isValidTTY("/dev/console") && !SessionLocator.isValidTTY("ttys001"),
              "only /dev/ttysNNN terminal devices are accepted")
        let script = SessionLocator.focusScript(bundleID: SessionLocator.iTermBundleID, tty: "/dev/ttys004")
        check(script?.contains("\"/dev/ttys004\"") == true && script?.contains("select t") == true,
              "the iTerm2 script selects the tab with that terminal")
        check(SessionLocator.focusScript(bundleID: SessionLocator.terminalBundleID, tty: "/dev/ttys004")?.contains("selected tab") == true,
              "Terminal.app tabs can be selected too")
        check(SessionLocator.focusScript(bundleID: SessionLocator.iTermBundleID, tty: "/dev/ttys1\"x") == nil
              && SessionLocator.focusScript(bundleID: "com.example.other", tty: "/dev/ttys004") == nil,
              "no script for invalid terminals or unknown apps")
        _ = SessionLocator.locate(pid: getpid())
        check(SessionLocator.locate(pid: 999_999) == nil, "locating a missing process finds nothing and does not crash")

        // Click versus drag.
        check(PetClick.isClick(moved: false, held: 0.15), "a quick still press is a click")
        check(!PetClick.isClick(moved: false, held: 1.2), "a long still press is not a click")
        check(!PetClick.isClick(moved: true, held: 0.1), "a press that moved is a drag, not a click")
    }
}
