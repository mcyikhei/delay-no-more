import XCTest
@testable import DelayCore

final class CodexStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func event(_ session: String, _ kind: String, _ turn: String? = "turn", _ seconds: Double = 0,
                       status: String? = nil, id: String = UUID().uuidString) -> CodexHookEvent {
        CodexHookEvent(eventID: id, sessionID: session, turnID: turn, event: kind,
                       time: now.timeIntervalSince1970 + seconds, status: status)
    }

    func testDuplicateMalformedAndExpiredEventsCannotChangeWork() {
        var reducer = CodexStatusReducer()
        let start = event("one", "TurnStarted")
        reducer.receive(start, at: now)
        reducer.receive(start, at: now)
        reducer.receive(event("one", "Stop", "turn", 1, id: start.eventID), at: now.addingTimeInterval(1))
        reducer.receive(event("one", "Unrecognized"), at: now)
        reducer.receive(event("one", "ThreadStatus", status: "malformed"), at: now)
        reducer.receive(event("one", "Stop"), at: now.addingTimeInterval(31))
        XCTAssertEqual(reducer.snapshot.activity, .working)
        XCTAssertEqual(reducer.snapshot.activeCount, 1)
    }

    func testOldTimestampAndOldTurnCannotEndCurrentWork() {
        var reducer = CodexStatusReducer()
        reducer.receive(event("one", "TurnStarted", "current", 4), at: now.addingTimeInterval(4))
        reducer.receive(event("one", "PermissionRequest", "current", 3), at: now.addingTimeInterval(4))
        reducer.receive(event("one", "TurnCompleted", "old", 5, status: "completed"), at: now.addingTimeInterval(5))
        XCTAssertEqual(reducer.snapshot.activity, .working)
    }

    func testApprovalPriorityAndRealActivityClearingWaiting() {
        var reducer = CodexStatusReducer()
        reducer.receive(event("unobserved", "SessionStart"), at: now)
        reducer.receive(event("one", "TurnStarted"), at: now)
        reducer.receive(event("two", "TurnStarted"), at: now)
        XCTAssertEqual(reducer.snapshot.activity, .working)
        reducer.receive(event("one", "PermissionRequest", "turn", 1), at: now.addingTimeInterval(1))
        XCTAssertEqual(reducer.snapshot.activity, .waiting)
        reducer.acknowledgeCompletion(at: now.addingTimeInterval(1))
        XCTAssertEqual(reducer.snapshot.activity, .waiting)
        reducer.receive(event("one", "PreToolUse", "turn", 2), at: now.addingTimeInterval(2))
        reducer.receive(event("two", "Stop", "turn", 3), at: now.addingTimeInterval(3))
        XCTAssertEqual(reducer.snapshot.activity, .working)
        XCTAssertNil(reducer.snapshot.cue)
    }

    func testFinishedLatchesUntilAcknowledgedAndLaterCompletionRelatches() {
        var reducer = CodexStatusReducer()
        reducer.receive(event("one", "TurnStarted"), at: now)
        let completion = event("one", "TurnCompleted", "turn", 1, status: "completed")
        reducer.receive(completion, at: now.addingTimeInterval(1))
        reducer.refresh(at: now.addingTimeInterval(1000))
        XCTAssertEqual(reducer.snapshot.activity, .finished)
        reducer.acknowledgeCompletion(at: now.addingTimeInterval(1000))
        XCTAssertEqual(reducer.snapshot.activity, .idle)
        reducer.receive(completion, at: now.addingTimeInterval(1))
        XCTAssertEqual(reducer.snapshot.activity, .idle)
        reducer.receive(event("one", "TurnStarted", "next", 1001), at: now.addingTimeInterval(1001))
        reducer.receive(event("one", "TurnCompleted", "next", 1002, status: "completed"), at: now.addingTimeInterval(1002))
        XCTAssertEqual(reducer.snapshot.activity, .finished)
    }

    func testFailureLatchesUntilNewCycleAndHasPriorityOverFinished() {
        var reducer = CodexStatusReducer()
        reducer.receive(event("one", "TurnStarted"), at: now)
        reducer.receive(event("two", "TurnStarted"), at: now)
        reducer.receive(event("one", "TurnCompleted", "turn", 1, status: "failed"), at: now.addingTimeInterval(1))
        XCTAssertEqual(reducer.snapshot.activity, .working)
        reducer.receive(event("two", "TurnCompleted", "turn", 2, status: "completed"), at: now.addingTimeInterval(2))
        XCTAssertEqual(reducer.snapshot.activity, .failed)
        reducer.acknowledgeCompletion(at: now.addingTimeInterval(2))
        reducer.refresh(at: now.addingTimeInterval(1000))
        XCTAssertEqual(reducer.snapshot.activity, .failed)
        reducer.receive(event("one", "Stop", "turn", 1001), at: now.addingTimeInterval(1001))
        XCTAssertEqual(reducer.snapshot.activity, .failed)
        reducer.receive(event("three", "TurnStarted", "new", 1002), at: now.addingTimeInterval(1002))
        XCTAssertEqual(reducer.snapshot.activity, .working)
    }

    func testExplicitInterruptEndsActivityButGenericStopPreservesWorking() {
        var reducer = CodexStatusReducer()
        reducer.receive(event("one", "TurnStarted"), at: now)
        reducer.receive(event("one", "Interrupt", "turn", 1), at: now.addingTimeInterval(1))
        XCTAssertEqual(reducer.snapshot.activity, .idle)
        XCTAssertEqual(reducer.snapshot.cue, .interrupted)
        reducer.receive(event("one", "PostToolUse", "turn", 2), at: now.addingTimeInterval(2))
        XCTAssertEqual(reducer.snapshot.activity, .working)
        reducer.receive(event("one", "Stop", "turn", 3), at: now.addingTimeInterval(3))
        XCTAssertEqual(reducer.snapshot.activity, .working)
        XCTAssertNil(reducer.snapshot.cue)
    }

    func testWorkHasNoNeutralGapBeforeExplicitCompletion() {
        var reducer = CodexStatusReducer()
        var states: [CodexActivity] = []
        reducer.receive(event("one", "TurnStarted"), at: now)
        states.append(reducer.snapshot.activity)
        reducer.receive(event("one", "Stop", "turn", 1), at: now.addingTimeInterval(1))
        states.append(reducer.snapshot.activity)
        reducer.receive(event("one", "SessionEnd", "turn", 2), at: now.addingTimeInterval(2))
        states.append(reducer.snapshot.activity)
        reducer.refresh(at: now.addingTimeInterval(86_400))
        states.append(reducer.snapshot.activity)
        XCTAssertEqual(reducer.snapshot.activeCount, 1)
        reducer.receive(event("one", "TurnCompleted", "turn", 86_401, status: "completed"), at: now.addingTimeInterval(86_401))
        states.append(reducer.snapshot.activity)
        XCTAssertEqual(states, [.working, .working, .working, .working, .finished])
        reducer.acknowledgeCompletion(at: now.addingTimeInterval(86_402))
        XCTAssertEqual(reducer.snapshot.activity, .idle)
        reducer.disconnect()
        XCTAssertEqual(reducer.snapshot, CodexStatusSnapshot())
    }

    func testWaitingLatchesAcrossStopSessionEndAndSilenceUntilActivity() {
        var reducer = CodexStatusReducer()
        reducer.receive(event("one", "TurnStarted"), at: now)
        reducer.receive(event("one", "PermissionRequest", "turn", 1), at: now.addingTimeInterval(1))
        reducer.receive(event("one", "Stop", "turn", 2), at: now.addingTimeInterval(2))
        reducer.receive(event("one", "SessionEnd", "turn", 3), at: now.addingTimeInterval(3))
        reducer.refresh(at: now.addingTimeInterval(86_400))
        XCTAssertEqual(reducer.snapshot.activity, .waiting)
        XCTAssertEqual(reducer.snapshot.activeCount, 1)
        reducer.receive(event("one", "PreToolUse", "turn", 86_401), at: now.addingTimeInterval(86_401))
        XCTAssertEqual(reducer.snapshot.activity, .working)
    }

    func testMissingIDsOnStopAndSessionEndPreserveKnownTurnForCompletion() {
        var reducer = CodexStatusReducer()
        reducer.receive(event("one", "TurnStarted", "known"), at: now)
        reducer.receive(event("one", "Stop", nil, 1), at: now.addingTimeInterval(1))
        reducer.receive(event("one", "SessionEnd", nil, 2), at: now.addingTimeInterval(2))
        reducer.refresh(at: now.addingTimeInterval(86_400))
        XCTAssertEqual(reducer.snapshot.activity, .working)
        XCTAssertTrue(reducer.isTracking(session: "one", turn: "known"))
        reducer.receive(event("one", "TurnCompleted", "known", 86_401, status: "completed"), at: now.addingTimeInterval(86_401))
        XCTAssertEqual(reducer.snapshot.activity, .finished)
    }

    func testNewPromptWithoutIDInvalidatesOldCompletionUntilFreshTurnArrives() {
        var reducer = CodexStatusReducer()
        reducer.receive(event("one", "TurnStarted", "old"), at: now)
        reducer.receive(event("one", "UserPromptSubmit", nil, 1), at: now.addingTimeInterval(1))
        reducer.receive(event("one", "TurnCompleted", "old", 2, status: "completed"), at: now.addingTimeInterval(2))
        XCTAssertEqual(reducer.snapshot.activity, .working)
        XCTAssertFalse(reducer.isTracking(session: "one", turn: "old"))
        reducer.receive(event("one", "PreToolUse", "fresh", 3), at: now.addingTimeInterval(3))
        reducer.receive(event("one", "TurnCompleted", "old", 4, status: "failed"), at: now.addingTimeInterval(4))
        XCTAssertEqual(reducer.snapshot.activity, .working)
        XCTAssertTrue(reducer.isTracking(session: "one", turn: "fresh"))
        reducer.receive(event("one", "TurnCompleted", "fresh", 5, status: "completed"), at: now.addingTimeInterval(5))
        XCTAssertEqual(reducer.snapshot.activity, .finished)
    }

    func testOtherRootStopAndSessionEndCannotHideUnresolvedWork() {
        var reducer = CodexStatusReducer()
        reducer.receive(event("one", "TurnStarted"), at: now)
        reducer.receive(event("two", "TurnStarted"), at: now)
        reducer.receive(event("two", "Stop", "turn", 1), at: now.addingTimeInterval(1))
        reducer.receive(event("two", "SessionEnd", "turn", 2), at: now.addingTimeInterval(2))
        reducer.receive(event("one", "TurnCompleted", "turn", 3, status: "completed"), at: now.addingTimeInterval(3))
        XCTAssertEqual(reducer.snapshot.activity, .working)
        XCTAssertEqual(reducer.snapshot.activeCount, 1)
        reducer.receive(event("two", "TurnCompleted", "turn", 4, status: "completed"), at: now.addingTimeInterval(4))
        XCTAssertEqual(reducer.snapshot.activity, .finished)
    }
}
