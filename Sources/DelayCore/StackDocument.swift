import Foundation

public enum StackError: LocalizedError, Equatable {
    case blankName
    case unsupportedVersion(Int)
    case duplicateIDs
    case invalidWindowPosition

    public var errorDescription: String? {
        switch self {
        case .blankName: return "Enter a task name."
        case .unsupportedVersion(let version):
            return "This stack uses file version \(version). Open it with a compatible version of Delay No More."
        case .duplicateIDs: return "The saved stack contains duplicate task IDs. The original file has been preserved."
        case .invalidWindowPosition: return "The saved window position is invalid. The original file has been preserved."
        }
    }
}

public enum CardColor: String, Codable, CaseIterable, Sendable {
    case pink, lemon, mint, blue, lilac

    fileprivate static func atPosition(_ position: Int) -> CardColor {
        let palette = allCases
        return palette[max(0, position) % palette.count]
    }
}

public struct TaskItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public let color: CardColor

    private enum CodingKeys: String, CodingKey { case id, name, color }

    public init(id: UUID = UUID(), name: String, color: CardColor = .pink) {
        self.id = id
        self.name = name
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        // Legacy documents drew colors by saved row. Keep that appearance
        // when loading a row written before the color field existed.
        color = try values.decodeIfPresent(CardColor.self, forKey: .color)
            ?? CardColor.atPosition(decoder.codingPath.last?.intValue ?? 0)
    }
}

public enum DockEdge: String, Codable, Sendable {
    case left, right
}

public struct WindowPlacement: Codable, Equatable, Sendable {
    /// Expanded panel's left edge, in AppKit global screen coordinates.
    public var x: Double?
    /// Expanded panel's TOP edge (not its origin/minY), in AppKit global screen coordinates.
    public var y: Double?
    public var screenID: UInt32?
    public var dockEdge: DockEdge?

    public init(x: Double? = nil, y: Double? = nil, screenID: UInt32? = nil, dockEdge: DockEdge? = nil) {
        self.x = x
        self.y = y
        self.screenID = screenID
        self.dockEdge = dockEdge
    }
}

public struct RemovedTask: Equatable, Sendable {
    public let task: TaskItem
    public let index: Int

    public init(task: TaskItem, index: Int) {
        self.task = task
        self.index = index
    }
}

public struct StackDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var tasks: [TaskItem]
    public var window: WindowPlacement

    public var nextCardColor: CardColor { CardColor.atPosition(tasks.count) }

    private enum CodingKeys: String, CodingKey { case version, tasks, window }

    public init(version: Int = 2, tasks: [TaskItem] = [], window: WindowPlacement = .init()) {
        self.version = version
        self.tasks = tasks
        self.window = window
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let savedVersion = try values.decode(Int.self, forKey: .version)
        guard savedVersion == 1 || savedVersion == 2 else { throw StackError.unsupportedVersion(savedVersion) }
        // Schema 1's retired fields are ignored. JSONStorage preserves its
        // original bytes before the first normal save writes schema 2.
        version = 2
        tasks = try values.decode([TaskItem].self, forKey: .tasks)
        window = try values.decode(WindowPlacement.self, forKey: .window)
    }

    public func validate() throws {
        guard version == 2 else { throw StackError.unsupportedVersion(version) }
        guard Set(tasks.map(\.id)).count == tasks.count else { throw StackError.duplicateIDs }
        for task in tasks {
            _ = try Self.validName(task.name)
        }
        if let x = window.x, !x.isFinite { throw StackError.invalidWindowPosition }
        if let y = window.y, !y.isFinite { throw StackError.invalidWindowPosition }
    }

    @discardableResult
    public mutating func push(name: String) throws -> TaskItem {
        let task = TaskItem(name: try Self.validName(name), color: nextCardColor)
        tasks.insert(task, at: 0)
        return task
    }

    /// The destination is the final numbered index after removing this card.
    public mutating func move(id: UUID, to index: Int) {
        guard let oldIndex = tasks.firstIndex(where: { $0.id == id }) else { return }
        let task = tasks.remove(at: oldIndex)
        tasks.insert(task, at: min(max(0, index), tasks.count))
    }

    @discardableResult
    public mutating func complete(id: UUID) -> RemovedTask? {
        // Stable identity prevents a repeated click on a disappearing card
        // from completing whichever card has become the new top task.
        guard tasks.first?.id == id else { return nil }
        return RemovedTask(task: tasks.removeFirst(), index: 0)
    }

    public mutating func restore(_ removal: RemovedTask) {
        guard !tasks.contains(where: { $0.id == removal.task.id }) else { return }
        tasks.insert(removal.task, at: min(max(0, removal.index), tasks.count))
    }

    private static func validName(_ name: String) throws -> String {
        let result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw StackError.blankName }
        return result
    }
}
