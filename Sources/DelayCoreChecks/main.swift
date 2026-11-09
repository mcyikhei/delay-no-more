import Foundation
import CoreGraphics
import DelayCore

// Runs without XCTest, so core behavior can be checked with Command Line Tools.
struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw CheckFailure(description: message) }
}

func expectThrows(_ message: String, _ operation: () throws -> Void) throws {
    do { try operation() }
    catch { return }
    throw CheckFailure(description: message)
}

func unwrap<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw CheckFailure(description: message) }
    return value
}

func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DelayNoMore-checks-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

func legacyData() -> Data {
    Data("""
    {
      "version": 1,
      "tasks": [
        { "id": "11111111-1111-1111-1111-111111111111", "name": "旧 task 🐈", "deadline": { "day": { "year": 2026, "month": 11, "day": 4 } } },
        { "id": "22222222-2222-2222-2222-222222222222", "name": "Timed card", "color": "mint", "deadline": { "instant": { "_0": "2026-11-04T10:00:00Z" } } }
      ],
      "window": { "x": -100, "y": 500, "screenID": 42, "dockEdge": "left" }
    }
    """.utf8)
}

var total = 0
var failures: [String] = []
func check(_ name: String, _ body: () throws -> Void) {
    total += 1
    do {
        try body()
        print("PASS: \(name)")
    } catch {
        failures.append(name)
        print("FAIL: \(name): \(error)")
    }
}

check("New captures always push onto the top") {
    var stack = StackDocument()
    let a = try stack.push(name: "A")
    let b = try stack.push(name: "B")
    try expect(stack.tasks.map(\.id) == [b.id, a.id], "Push did not use newest-first order")
    try expect(stack.version == 2, "New documents use the wrong schema")
}

check("Only the current top completes and stale IDs cannot pop the next task") {
    var stack = StackDocument()
    let lower = try stack.push(name: "Lower")
    let top = try stack.push(name: "Top")
    try expect(stack.complete(id: lower.id) == nil, "Completed a lower task")
    try expect(stack.complete(id: top.id)?.task == top, "Top task did not complete")
    try expect(stack.complete(id: top.id) == nil && stack.tasks == [lower], "Repeated completion popped another task")
}

check("Names preserve Unicode and duplicates while rejecting blanks") {
    var stack = StackDocument()
    for blank in ["", " \n\t ", "\u{00a0}"] {
        try expectThrows("Accepted a blank name") { _ = try stack.push(name: blank) }
    }
    let a = try stack.push(name: "  薬局 🐈 café  ")
    let b = try stack.push(name: "薬局 🐈 café")
    try expect(a.name == "薬局 🐈 café" && a.name == b.name && a.id != b.id, "Name or identity handling changed")
}

check("Reordering uses final indices and clamps both endpoints") {
    var stack = StackDocument()
    let a = try stack.push(name: "A")
    let b = try stack.push(name: "B")
    let c = try stack.push(name: "C")
    stack.move(id: c.id, to: 2)
    try expect(stack.tasks.map(\.id) == [b.id, a.id, c.id], "Downward move used the wrong index")
    stack.move(id: a.id, to: -10)
    try expect(stack.tasks.map(\.id) == [a.id, b.id, c.id], "Top clamp failed")
    stack.move(id: a.id, to: .max)
    try expect(stack.tasks.map(\.id) == [b.id, c.id, a.id], "Bottom clamp failed")
    let original = stack
    stack.move(id: UUID(), to: 0)
    try expect(stack == original, "Unknown ID changed the stack")
}

check("Undo preserves intervening pushes and reordering") {
    var stack = StackDocument()
    let a = try stack.push(name: "A")
    let b = try stack.push(name: "B")
    let removed = try unwrap(stack.complete(id: b.id), "Missing completion")
    let c = try stack.push(name: "C")
    stack.move(id: a.id, to: 0)
    stack.restore(removed)
    try expect(stack.tasks.map(\.id) == [b.id, a.id, c.id], "Undo discarded intervening changes")
    stack.restore(removed)
    try expect(stack.tasks.count == 3, "Duplicate Undo duplicated a card")
}

check("Undo clamps a former position when the remaining stack is shorter") {
    var stack = StackDocument()
    let task = TaskItem(name: "Restored", color: .mint)
    stack.restore(RemovedTask(task: task, index: 9))
    try expect(stack.tasks == [task], "Undo did not clamp its insertion position")
}

check("Validation rejects unsupported versions, duplicate IDs, and blank saved names") {
    try expectThrows("Accepted unsupported version") { try StackDocument(version: 3).validate() }
    let task = TaskItem(name: "A")
    try expectThrows("Accepted duplicate IDs") { try StackDocument(tasks: [task, task]).validate() }
    try expectThrows("Accepted blank saved name") { try StackDocument(tasks: [TaskItem(name: " ")]).validate() }
}

check("A hundred captures retain their exact order") {
    var stack = StackDocument()
    for number in 0..<100 { try stack.push(name: String(number)) }
    try expect(stack.tasks.map(\.name) == (0..<100).reversed().map(String.init), "Large stack lost order")
    try stack.validate()
}

check("Colors follow active count and remain attached through moves and Undo") {
    var stack = StackDocument()
    var created: [TaskItem] = []
    for color in CardColor.allCases {
        try expect(stack.nextCardColor == color, "Preview color did not follow active count")
        let task = try stack.push(name: color.rawValue)
        try expect(task.color == color, "Capture used a different color")
        created.append(task)
    }
    stack.move(id: created[0].id, to: 0)
    try expect(stack.tasks.first?.color == .pink && stack.nextCardColor == .pink, "Moving changed a permanent color")
    let removed = try unwrap(stack.complete(id: created[0].id), "Missing completion")
    try expect(stack.nextCardColor == .lilac, "Completion did not change active count")
    stack.restore(removed)
    try expect(stack.tasks.first?.color == .pink && stack.nextCardColor == .pink, "Undo changed color or count")
}

check("Missing storage loads an empty schema 2 document without writing") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("new/stack.json"))
        try expect(try storage.load() == StackDocument(), "Missing file did not load empty")
        try expect(!FileManager.default.fileExists(atPath: storage.url.path), "Read created a file")
    }
}

check("Atomic schema 2 roundtrip preserves tasks, colors, order, and placement") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("nested/stack.json"))
        var document = StackDocument(window: WindowPlacement(x: -123, y: 55, screenID: 42, dockEdge: .right))
        try document.push(name: "薬局 🐈")
        try document.push(name: "Next task")
        try storage.save(document)
        try expect(try storage.load() == document, "Roundtrip changed the stack")
        _ = document.complete(id: document.tasks[0].id)
        try storage.save(document)
        try expect(try storage.load() == document, "Atomic replacement did not commit")
        try expect(!FileManager.default.fileExists(atPath: storage.migrationBackupURL.path), "New schema 2 data created a legacy backup")
        let files = try FileManager.default.contentsOfDirectory(atPath: storage.url.deletingLastPathComponent().path)
        try expect(files == ["stack.json"], "Save left intermediate files")
    }
}

check("Corrupt storage is preserved by read and save attempts") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("stack.json"))
        let original = Data("{ invalid json".utf8)
        try original.write(to: storage.url)
        try expectThrows("Loaded corrupt storage") { _ = try storage.load() }
        try expectThrows("Overwrote corrupt storage") { try storage.save(StackDocument()) }
        try expect(try Data(contentsOf: storage.url) == original, "Original corrupt file changed")
    }
}

check("Future storage versions remain untouched") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("stack.json"))
        let original = try JSONEncoder().encode(StackDocument(version: 3))
        try original.write(to: storage.url)
        try expectThrows("Loaded future schema") { _ = try storage.load() }
        try expectThrows("Overwrote future schema") { try storage.save(StackDocument()) }
        try expect(try Data(contentsOf: storage.url) == original, "Future file changed")
    }
}

check("Invalid saved names and duplicate IDs cannot be loaded or overwritten") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("stack.json"))
        let task = TaskItem(name: "Duplicate")
        for document in [StackDocument(tasks: [task, task]), StackDocument(tasks: [TaskItem(name: " ")])] {
            let original = try JSONEncoder().encode(document)
            try original.write(to: storage.url)
            try expectThrows("Loaded invalid saved tasks") { _ = try storage.load() }
            try expectThrows("Overwrote invalid saved tasks") { try storage.save(StackDocument()) }
            try expect(try Data(contentsOf: storage.url) == original, "Invalid original changed")
        }
    }
}

check("Write failures leave an obstructing file intact") {
    try withDirectory { directory in
        let blocker = directory.appendingPathComponent("blocker")
        let original = Data("Keep me".utf8)
        try original.write(to: blocker)
        let storage = JSONStorage(url: blocker.appendingPathComponent("stack.json"))
        try expectThrows("Saved through an obstructing file") { try storage.save(StackDocument()) }
        try expect(try Data(contentsOf: blocker) == original, "Write failure altered a file")
    }
}

check("An invalid candidate cannot replace the last committed stack") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("stack.json"))
        var valid = StackDocument()
        try valid.push(name: "Keep")
        try storage.save(valid)
        try expectThrows("Saved an invalid candidate") { try storage.save(StackDocument(tasks: [TaskItem(name: "")])) }
        try expect(try storage.load() == valid, "Invalid candidate replaced committed data")
    }
}

check("Legacy data migrates with an exact original backup before first rewrite") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("stack.json"))
        let original = legacyData()
        try original.write(to: storage.url)
        var document = try storage.load()
        try expect(document.version == 2 && document.tasks.map(\.color) == [.pink, .mint], "Legacy schema or colors did not migrate")
        try expect(try Data(contentsOf: storage.url) == original, "Loading rewrote the source")
        try expect(!FileManager.default.fileExists(atPath: storage.migrationBackupURL.path), "Loading created a backup")
        document.move(id: document.tasks[1].id, to: 0)
        try document.push(name: "New card")
        try storage.save(document)
        try expect(try Data(contentsOf: storage.migrationBackupURL) == original, "Original backup is not byte-for-byte identical")
        try expect(try storage.load() == document, "Migration lost active data or placement")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: storage.url)) as! [String: Any]
        let tasks = saved["tasks"] as! [[String: Any]]
        try expect(saved["version"] as? Int == 2 && tasks.allSatisfy { $0["deadline"] == nil }, "Retired fields survived schema 2 encoding")
    }
}

check("Backup failure blocks migration and preserves source bytes") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("stack.json"))
        let original = legacyData()
        try original.write(to: storage.url)
        try FileManager.default.createDirectory(at: storage.migrationBackupURL, withIntermediateDirectories: true)
        let document = try storage.load()
        try expectThrows("Migration proceeded without a usable backup") { try storage.save(document) }
        try expect(try Data(contentsOf: storage.url) == original, "Failed backup changed the source")
    }
}

check("A different existing backup is preserved and blocks migration") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("stack.json"))
        let original = legacyData()
        let previousBackup = Data("Existing backup must survive".utf8)
        try original.write(to: storage.url)
        try previousBackup.write(to: storage.migrationBackupURL)
        try expectThrows("Overwrote a different backup") { try storage.save(storage.load()) }
        try expect(try Data(contentsOf: storage.url) == original, "Backup conflict changed source")
        try expect(try Data(contentsOf: storage.migrationBackupURL) == previousBackup, "Backup conflict changed existing backup")
    }
}

check("A matching interrupted-migration backup is reused exactly once") {
    try withDirectory { directory in
        let storage = JSONStorage(url: directory.appendingPathComponent("stack.json"))
        let original = legacyData()
        try original.write(to: storage.url)
        try original.write(to: storage.migrationBackupURL)
        var document = try storage.load()
        try storage.save(document)
        try document.push(name: "After migration")
        try storage.save(document)
        try expect(try storage.load() == document, "Retry or normal save lost the stack")
        try expect(try Data(contentsOf: storage.migrationBackupURL) == original, "Later save changed the original backup")
        try expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2, "Migration left extra files")
    }
}

check("Flipped and unflipped content normalize to the same root point") {
    let bounds = CGRect(x: 10, y: 20, width: 320, height: 500)
    let unflipped = PetHitRegions.topDownPoint(CGPoint(x: 60, y: 450), in: bounds, isFlipped: false)
    let flipped = PetHitRegions.topDownPoint(CGPoint(x: 60, y: 90), in: bounds, isFlipped: true)
    try expect(unflipped == CGPoint(x: 50, y: 70) && flipped == unflipped, "Content origin or y-axis conversion was wrong")
}

check("Negative content origins stay in logical points without retina scaling") {
    let bounds = CGRect(x: -200, y: -80, width: 320, height: 500)
    let point = PetHitRegions.topDownPoint(CGPoint(x: -125, y: 380), in: bounds, isFlipped: false)
    try expect(point == CGPoint(x: 75, y: 40), "Point was scaled or origin was not normalized")
}

check("Mouth center blocks dragging while ellipse bounding-box corners do not") {
    let bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
    let mouth = CGRect(x: 24, y: 5, width: 272, height: 34)
    let center = CGPoint(x: 160, y: 22)
    let corner = CGPoint(x: 25, y: 6)
    try expect(PetHitRegions.containsEllipse(center, in: mouth), "Mouth center was not interactive")
    try expect(!PetHitRegions.containsEllipse(corner, in: mouth), "Ellipse incorrectly used its bounding rectangle")
    try expect(!PetHitRegions.isBackgroundDrag(at: center, in: bounds, mouth: mouth, protectedRects: []), "Mouth started pet drag")
    try expect(PetHitRegions.isBackgroundDrag(at: corner, in: bounds, mouth: mouth, protectedRects: []), "Corner was incorrectly protected as mouth")
}

check("Degenerate and nonfinite ellipses cannot claim hit regions") {
    try expect(!PetHitRegions.containsEllipse(.zero, in: .zero), "Zero-sized mouth was hittable")
    try expect(!PetHitRegions.containsEllipse(.zero, in: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 40)), "Infinite ellipse was hittable")
    try expect(!PetHitRegions.containsEllipse(CGPoint(x: CGFloat.nan, y: 2), in: CGRect(x: 0, y: 0, width: 30, height: 40)), "NaN point was hittable")
}

check("Cards, editor, and base controls take precedence over pet drag") {
    let bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
    let mouth = CGRect(x: 24, y: 5, width: 272, height: 34)
    let protected = [CGRect(x: 38, y: 62, width: 244, height: 70),
                     CGRect(x: 38, y: 150, width: 244, height: 250),
                     CGRect(x: 50, y: 450, width: 30, height: 30)]
    for point in [CGPoint(x: 80, y: 90), CGPoint(x: 100, y: 200), CGPoint(x: 65, y: 465)] {
        try expect(!PetHitRegions.isBackgroundDrag(at: point, in: bounds, mouth: mouth, protectedRects: protected), "An interactive region started pet drag")
    }
    try expect(PetHitRegions.isBackgroundDrag(at: CGPoint(x: 30, y: 250), in: bounds, mouth: mouth, protectedRects: protected), "Empty vessel side could not drag")
}

check("Clipped scrolled cards protect only their visible part") {
    let bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
    let mouth = CGRect(x: 24, y: 5, width: 272, height: 34)
    let viewport = CGRect(x: 38, y: 60, width: 244, height: 350)
    let partial = CGRect(x: 38, y: 380, width: 244, height: 70).intersection(viewport)
    let offscreen = CGRect(x: 38, y: 450, width: 244, height: 70).intersection(viewport)
    try expect(!PetHitRegions.isBackgroundDrag(at: CGPoint(x: 100, y: 400), in: bounds, mouth: mouth, protectedRects: [partial, offscreen]), "Visible card portion did not protect drag")
    try expect(PetHitRegions.isBackgroundDrag(at: CGPoint(x: 100, y: 430), in: bounds, mouth: mouth, protectedRects: [partial, offscreen]), "Offscreen card portion blocked the pet")
}

check("Out-of-bounds and invalid geometry fail closed") {
    let bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
    let mouth = CGRect(x: 24, y: 5, width: 272, height: 34)
    for point in [CGPoint(x: -1, y: 100), CGPoint(x: 320, y: 100), CGPoint(x: 20, y: 501), CGPoint(x: CGFloat.nan, y: 100)] {
        try expect(!PetHitRegions.isBackgroundDrag(at: point, in: bounds, mouth: mouth, protectedRects: []), "An invalid point intercepted an event")
    }
    try expect(!PetHitRegions.isBackgroundDrag(at: CGPoint(x: 30, y: 100), in: bounds, mouth: .zero, protectedRects: []), "Missing mouth geometry did not fail closed")
}

check("Panel resizing uses the current height in AppKit conversion") {
    let local = CGPoint(x: 100, y: 280)
    let short = PetHitRegions.topDownPoint(local, in: CGRect(x: 0, y: 0, width: 320, height: 300), isFlipped: false)
    let tall = PetHitRegions.topDownPoint(local, in: CGRect(x: 0, y: 0, width: 320, height: 500), isFlipped: false)
    try expect(short == CGPoint(x: 100, y: 20) && tall == CGPoint(x: 100, y: 220), "Resize reused stale y-axis bounds")
}

check("A click or small pointer jitter does not move the pet") {
    var drag = PetWindowDrag(pointer: CGPoint(x: 80, y: 200), windowOrigin: CGPoint(x: 50, y: 40))
    try expect(drag.move(to: CGPoint(x: 82, y: 201)) == nil && !drag.hasMoved,
               "A press below the drag threshold changed the window position")
    try expect(drag.move(to: CGPoint(x: 83, y: 200)) == CGPoint(x: 53, y: 40) && drag.hasMoved,
               "The drag did not start at the movement threshold")
}

check("Dragging keeps the original grip offset across pointer updates") {
    var drag = PetWindowDrag(pointer: CGPoint(x: 80, y: 200), windowOrigin: CGPoint(x: 50, y: 40))
    try expect(drag.move(to: CGPoint(x: 120, y: 190)) == CGPoint(x: 90, y: 30), "Wrong first drag offset")
    try expect(drag.move(to: CGPoint(x: -25, y: 220)) == CGPoint(x: -55, y: 60), "Offset drifted across displays")
    try expect(drag.move(to: CGPoint(x: 80, y: 200)) == CGPoint(x: 50, y: 40), "Returning to the start did not restore the origin")
}

check("Codex work remains blue until explicit completion without a neutral gap") {
    let origin = Date(timeIntervalSince1970: 1_700_000_000)
    var reducer = CodexStatusReducer()
    var states: [CodexActivity] = []
    for (kind, seconds) in [("TurnStarted", 0.0), ("Stop", 1.0), ("SessionEnd", 2.0)] {
        let now = origin.addingTimeInterval(seconds)
        let turn = kind == "TurnStarted" ? "turn" : nil
        reducer.receive(CodexHookEvent(sessionID: "one", turnID: turn, event: kind, time: now.timeIntervalSince1970), at: now)
        states.append(reducer.snapshot.activity)
    }
    reducer.refresh(at: origin.addingTimeInterval(86_400))
    states.append(reducer.snapshot.activity)
    try expect(reducer.isTracking(session: "one", turn: "turn"), "ID-less Stop or SessionEnd discarded the known turn")
    let finished = origin.addingTimeInterval(86_401)
    reducer.receive(CodexHookEvent(sessionID: "one", turnID: "turn", event: "TurnCompleted",
                                  time: finished.timeIntervalSince1970, status: "completed"), at: finished)
    states.append(reducer.snapshot.activity)
    try expect(states == [.working, .working, .working, .working, .finished], "Stop, SessionEnd, or silence inserted a neutral state before completion")
    reducer.acknowledgeCompletion(at: finished)
    try expect(reducer.snapshot.activity == .idle, "Acknowledging did not clear the completed result")
}

check("Codex waiting remains latched until work or an explicit outcome resumes") {
    let origin = Date(timeIntervalSince1970: 1_700_000_000)
    var reducer = CodexStatusReducer()
    for (kind, seconds) in [("TurnStarted", 0.0), ("PermissionRequest", 1.0), ("Stop", 2.0), ("SessionEnd", 3.0)] {
        let now = origin.addingTimeInterval(seconds)
        reducer.receive(CodexHookEvent(sessionID: "one", turnID: "turn", event: kind, time: now.timeIntervalSince1970), at: now)
    }
    reducer.refresh(at: origin.addingTimeInterval(86_400))
    try expect(reducer.snapshot.activity == .waiting && reducer.snapshot.activeCount == 1, "Pending waiting expired before any resolution")
    let resumed = origin.addingTimeInterval(86_401)
    reducer.receive(CodexHookEvent(sessionID: "one", turnID: "turn", event: "PreToolUse", time: resumed.timeIntervalSince1970), at: resumed)
    try expect(reducer.snapshot.activity == .working, "Resumed activity did not clear approval waiting")
}

check("An unidentified new Codex turn cannot accept the previous turn's outcome") {
    let origin = Date(timeIntervalSince1970: 1_700_000_000)
    var reducer = CodexStatusReducer()
    reducer.receive(CodexHookEvent(sessionID: "one", turnID: "old", event: "TurnStarted", time: origin.timeIntervalSince1970), at: origin)
    let submitted = origin.addingTimeInterval(1)
    reducer.receive(CodexHookEvent(sessionID: "one", event: "UserPromptSubmit", time: submitted.timeIntervalSince1970), at: submitted)
    let oldResult = origin.addingTimeInterval(2)
    reducer.receive(CodexHookEvent(sessionID: "one", turnID: "old", event: "TurnCompleted",
                                  time: oldResult.timeIntervalSince1970, status: "completed"), at: oldResult)
    try expect(reducer.snapshot.activity == .working && !reducer.isTracking(session: "one", turn: "old"), "An old result finished the unidentified new turn")
    let activity = origin.addingTimeInterval(3)
    reducer.receive(CodexHookEvent(sessionID: "one", turnID: "fresh", event: "PreToolUse", time: activity.timeIntervalSince1970), at: activity)
    let completion = origin.addingTimeInterval(4)
    reducer.receive(CodexHookEvent(sessionID: "one", turnID: "fresh", event: "TurnCompleted",
                                  time: completion.timeIntervalSince1970, status: "completed"), at: completion)
    try expect(reducer.snapshot.activity == .finished, "The fresh observed turn did not complete")
}

print("\nCore checks: \(total - failures.count)/\(total) passed")
if !failures.isEmpty { exit(1) }
