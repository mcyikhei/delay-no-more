import Foundation

public protocol StateStorage {
    func load() throws -> StackDocument
    func save(_ document: StackDocument) throws
}

public struct JSONStorage: StateStorage, Sendable {
    public let url: URL

    public var migrationBackupURL: URL {
        url.deletingPathExtension().appendingPathExtension("v1.backup.json")
    }

    private struct SchemaHeader: Decodable { let version: Int }

    private struct BackupError: LocalizedError {
        let path: String
        let reason: String
        var errorDescription: String? {
            "Couldn’t preserve the original stack at \(path). \(reason) The saved stack has not been changed."
        }
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DelayNoMore", isDirectory: true)
            .appendingPathComponent("stack.json", isDirectory: false)
    }

    public init(url: URL = JSONStorage.defaultURL) { self.url = url }

    public func load() throws -> StackDocument {
        guard let data = try existingData() else { return StackDocument() }
        return try decode(data)
    }

    public func save(_ document: StackDocument) throws {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)

        // Verify the current file before replacement, including after a prior
        // successful load. A corrupt or newer file remains untouched.
        if let original = try existingData() {
            _ = try decode(original)
            let header = try JSONDecoder().decode(SchemaHeader.self, from: original)
            if header.version == 1 { try preserveOriginal(original) }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func existingData() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    private func decode(_ data: Data) throws -> StackDocument {
        let document = try JSONDecoder().decode(StackDocument.self, from: data)
        try document.validate()
        return document
    }

    private func preserveOriginal(_ original: Data) throws {
        do {
            try original.write(to: migrationBackupURL, options: .withoutOverwriting)
        } catch {
            // A completed backup from a prior interrupted attempt is reusable.
            // A different or unreadable backup must never be overwritten.
            guard let saved = try? Data(contentsOf: migrationBackupURL), saved == original else {
                throw BackupError(path: migrationBackupURL.path, reason: error.localizedDescription)
            }
        }
        guard try Data(contentsOf: migrationBackupURL) == original else {
            throw BackupError(path: migrationBackupURL.path, reason: "The backup could not be verified.")
        }
    }
}
