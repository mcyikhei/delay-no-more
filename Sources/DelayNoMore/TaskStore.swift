import AppKit
import Combine
import DelayCore
import Foundation

/// One serial transaction boundary for every task and placement change.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var document = StackDocument()
    @Published private(set) var error: String?
    @Published private(set) var undoName: String?
    @Published private(set) var canEdit = false
    private let storage: any StateStorage
    private var removal: RemovedTask?
    private var undoExpires: Date?
    private var expiryTask: Task<Void, Never>?

    var tasks: [TaskItem] { document.tasks }
    var windowPlacement: WindowPlacement { document.window }

    init(storage: (any StateStorage)? = nil) {
        if let storage { self.storage = storage }
        else if let folder = ProcessInfo.processInfo.environment["DELAY_NO_MORE_DATA_DIR"] {
            self.storage = JSONStorage(url: URL(fileURLWithPath: folder).appendingPathComponent("stack.json"))
        } else { self.storage = JSONStorage() }
        retryLoad()
    }

    func retryLoad() {
        do {
            let loaded = try storage.load()
            document = loaded
            canEdit = true
            error = nil
        } catch {
            canEdit = false
            self.error = "Couldn’t read your stack. Your saved file has been preserved. \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func commit(_ change: (inout StackDocument) throws -> Void) -> Bool {
        guard canEdit else { return false }
        var candidate = document
        do {
            try change(&candidate)
            guard candidate != document else { return true }
            try storage.save(candidate)
            document = candidate
            error = nil
            return true
        } catch {
            self.error = "Couldn’t save this change. Your previous stack is safe. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func add(name: String) -> Bool {
        commit { _ = try $0.push(name: name) }
    }

    func move(id: UUID, to index: Int) { commit { $0.move(id: id, to: index) } }

    func complete(id: UUID) {
        guard tasks.first?.id == id else { return }
        var removed: RemovedTask?
        let saved = commit { document in
            removed = document.complete(id: id)
        }
        guard saved, let removed else { return }
        expiryTask?.cancel()
        removal = removed
        undoName = removed.task.name
        undoExpires = Date().addingTimeInterval(10)
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) }
            catch { return }
            self?.clearUndo()
        }
    }

    func undoRemoval() {
        guard let removal, let undoExpires, Date() < undoExpires else { clearUndo(); return }
        if commit({ $0.restore(removal) }) { clearUndo() }
    }

    private func clearUndo() {
        expiryTask?.cancel()
        expiryTask = nil
        removal = nil
        undoExpires = nil
        undoName = nil
    }

    func savePlacement(_ placement: WindowPlacement) {
        guard canEdit else { return }
        commit { $0.window = placement }
    }
}

/// Shared interaction state prevents auto-hide while the user is working.
@MainActor
final class AppInteraction: ObservableObject {
    @Published var tucked = false
    @Published var maxPanelHeight: CGFloat = TubeMetrics.height
    @Published var preferredHeight: CGFloat = TubeMetrics.height
    @Published var dragExclusions: [CGRect] = []
    @Published var isEditing = false
    @Published var hasOpenEditor = false
    @Published var draggingCard = false
    @Published var cardFlightActive = false
    @Published var isDocking = false
    var requestKeyboard: () -> Void = {}
    var finishEditing: () -> Void = {}
    func beginEditing() { isEditing = true; requestKeyboard() }
    func endEditing() { isEditing = false; finishEditing() }
}
