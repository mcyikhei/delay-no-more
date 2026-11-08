import XCTest
@testable import DelayCore

final class JSONStorageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DelayNoMore-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    private func storage() -> JSONStorage {
        JSONStorage(url: directory.appendingPathComponent("stack.json"))
    }

    private func legacyData() -> Data {
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

    func testMissingFileLoadsEmptyWithoutCreatingIt() throws {
        let store = JSONStorage(url: directory.appendingPathComponent("new/subdirectory/stack.json"))
        XCTAssertEqual(try store.load(), StackDocument())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testAtomicRoundtripPreservesTasksColorsOrderAndPlacement() throws {
        let store = storage()
        var document = StackDocument(window: WindowPlacement(x: -123, y: 55, screenID: 42, dockEdge: .right))
        try document.push(name: "薬局 🐈")
        try document.push(name: "Next task")
        try store.save(document)
        XCTAssertEqual(try store.load(), document)
        _ = document.complete(id: document.tasks[0].id)
        try store.save(document)
        XCTAssertEqual(try store.load(), document)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.migrationBackupURL.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["stack.json"])
    }

    func testCorruptFileIsPreservedByReadAndSaveAttempts() throws {
        let store = storage()
        let original = Data("{ not json".utf8)
        try original.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(StackDocument()))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }

    func testUnsupportedVersionRemainsUntouched() throws {
        let store = storage()
        let original = try JSONEncoder().encode(StackDocument(version: 3))
        try original.write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(StackDocument()))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }

    func testInvalidSavedNamesAndIDsCannotBeLoadedOrOverwritten() throws {
        let store = storage()
        let task = TaskItem(name: "Duplicate")
        for document in [StackDocument(tasks: [task, task]), StackDocument(tasks: [TaskItem(name: " ")])] {
            let original = try JSONEncoder().encode(document)
            try original.write(to: store.url)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.save(StackDocument()))
            XCTAssertEqual(try Data(contentsOf: store.url), original)
        }
    }

    func testWriteFailurePreservesObstructingFile() throws {
        let blocker = directory.appendingPathComponent("blocker")
        let original = Data("Keep me".utf8)
        try original.write(to: blocker)
        let store = JSONStorage(url: blocker.appendingPathComponent("stack.json"))
        XCTAssertThrowsError(try store.save(StackDocument()))
        XCTAssertEqual(try Data(contentsOf: blocker), original)
    }

    func testInvalidCandidateCannotReplaceLastCommittedStack() throws {
        let store = storage()
        var valid = StackDocument()
        try valid.push(name: "Keep")
        try store.save(valid)
        XCTAssertThrowsError(try store.save(StackDocument(tasks: [TaskItem(name: "")])) )
        XCTAssertEqual(try store.load(), valid)
    }

    func testLegacyMigrationBacksUpExactBytesBeforeFirstRewrite() throws {
        let store = storage()
        let original = legacyData()
        try original.write(to: store.url)
        var document = try store.load()
        XCTAssertEqual(document.version, 2)
        XCTAssertEqual(document.tasks.map(\.color), [.pink, .mint])
        XCTAssertEqual(try Data(contentsOf: store.url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.migrationBackupURL.path))
        document.move(id: document.tasks[1].id, to: 0)
        try document.push(name: "New card")
        try store.save(document)
        XCTAssertEqual(try Data(contentsOf: store.migrationBackupURL), original)
        XCTAssertEqual(try store.load(), document)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as! [String: Any]
        XCTAssertEqual(saved["version"] as? Int, 2)
        XCTAssertTrue((saved["tasks"] as! [[String: Any]]).allSatisfy { $0["deadline"] == nil })
    }

    func testBackupFailureBlocksMigrationAndPreservesSource() throws {
        let store = storage()
        let original = legacyData()
        try original.write(to: store.url)
        try FileManager.default.createDirectory(at: store.migrationBackupURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.save(store.load()))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }

    func testDifferentExistingBackupIsPreservedAndBlocksMigration() throws {
        let store = storage()
        let original = legacyData()
        let previousBackup = Data("Existing backup must survive".utf8)
        try original.write(to: store.url)
        try previousBackup.write(to: store.migrationBackupURL)
        XCTAssertThrowsError(try store.save(store.load()))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
        XCTAssertEqual(try Data(contentsOf: store.migrationBackupURL), previousBackup)
    }

    func testMatchingInterruptedBackupIsReusedAndLaterSavesLeaveItAlone() throws {
        let store = storage()
        let original = legacyData()
        try original.write(to: store.url)
        try original.write(to: store.migrationBackupURL)
        var document = try store.load()
        try store.save(document)
        try document.push(name: "After migration")
        try store.save(document)
        XCTAssertEqual(try store.load(), document)
        XCTAssertEqual(try Data(contentsOf: store.migrationBackupURL), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }
}
