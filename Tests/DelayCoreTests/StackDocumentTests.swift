import XCTest
@testable import DelayCore

final class StackDocumentTests: XCTestCase {
    func testCapturesPushOntoTop() throws {
        var stack = StackDocument()
        let a = try stack.push(name: "A")
        let b = try stack.push(name: "B")
        XCTAssertEqual(stack.tasks.map(\.id), [b.id, a.id])
        XCTAssertEqual(stack.version, 2)
    }

    func testOnlyCurrentTopCompletesAndRepeatedIDCannotPopNext() throws {
        var stack = StackDocument()
        let lower = try stack.push(name: "Lower")
        let top = try stack.push(name: "Top")
        XCTAssertNil(stack.complete(id: lower.id))
        XCTAssertEqual(stack.complete(id: top.id)?.task, top)
        XCTAssertNil(stack.complete(id: top.id))
        XCTAssertEqual(stack.tasks, [lower])
    }

    func testNamesPreserveUnicodeAndDuplicatesWhileRejectingBlanks() throws {
        var stack = StackDocument()
        for name in ["", " \n\t ", "\u{00a0}"] {
            XCTAssertThrowsError(try stack.push(name: name))
        }
        let first = try stack.push(name: "  薬局 🐈 café  ")
        let second = try stack.push(name: "薬局 🐈 café")
        XCTAssertEqual(first.name, "薬局 🐈 café")
        XCTAssertEqual(first.name, second.name)
        XCTAssertNotEqual(first.id, second.id)
    }

    func testMoveUsesFinalIndexAndClampsEndpoints() throws {
        var stack = StackDocument()
        let a = try stack.push(name: "A")
        let b = try stack.push(name: "B")
        let c = try stack.push(name: "C")
        stack.move(id: c.id, to: 2)
        XCTAssertEqual(stack.tasks.map(\.id), [b.id, a.id, c.id])
        stack.move(id: a.id, to: -10)
        XCTAssertEqual(stack.tasks.map(\.id), [a.id, b.id, c.id])
        stack.move(id: a.id, to: .max)
        XCTAssertEqual(stack.tasks.map(\.id), [b.id, c.id, a.id])
        let original = stack
        stack.move(id: UUID(), to: 0)
        XCTAssertEqual(stack, original)
    }

    func testUndoPreservesInterveningPushesAndReordering() throws {
        var stack = StackDocument()
        let a = try stack.push(name: "A")
        let b = try stack.push(name: "B")
        let removal = try XCTUnwrap(stack.complete(id: b.id))
        let c = try stack.push(name: "C")
        stack.move(id: a.id, to: 0)
        stack.restore(removal)
        XCTAssertEqual(stack.tasks.map(\.id), [b.id, a.id, c.id])
        stack.restore(removal)
        XCTAssertEqual(stack.tasks.count, 3)
    }

    func testRestoreClampsFormerPositionToCurrentStackSize() {
        var stack = StackDocument()
        let task = TaskItem(name: "Restored", color: .mint)
        stack.restore(RemovedTask(task: task, index: 9))
        XCTAssertEqual(stack.tasks, [task])
    }

    func testValidationRejectsUnsupportedVersionsDuplicateIDsAndBlankNames() {
        XCTAssertThrowsError(try StackDocument(version: 3).validate())
        let task = TaskItem(name: "A")
        XCTAssertThrowsError(try StackDocument(tasks: [task, task]).validate())
        XCTAssertThrowsError(try StackDocument(tasks: [TaskItem(name: " ")]).validate())
    }

    func testHundredCapturesRetainExactOrder() throws {
        var stack = StackDocument()
        for number in 0..<100 { try stack.push(name: String(number)) }
        XCTAssertEqual(stack.tasks.map(\.name), (0..<100).reversed().map(String.init))
        try stack.validate()
    }

    func testPermanentColorsFollowCountAndSurviveMovesAndUndo() throws {
        var stack = StackDocument()
        var created: [TaskItem] = []
        for color in CardColor.allCases {
            XCTAssertEqual(stack.nextCardColor, color)
            let task = try stack.push(name: color.rawValue)
            XCTAssertEqual(task.color, color)
            created.append(task)
        }
        stack.move(id: created[0].id, to: 0)
        XCTAssertEqual(stack.tasks.first?.color, .pink)
        XCTAssertEqual(stack.nextCardColor, .pink)
        let removed = try XCTUnwrap(stack.complete(id: created[0].id))
        XCTAssertEqual(stack.nextCardColor, .lilac)
        stack.restore(removed)
        XCTAssertEqual(stack.tasks.first?.color, .pink)
        XCTAssertEqual(stack.nextCardColor, .pink)
    }
}
