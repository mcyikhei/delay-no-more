import Foundation
import CoreGraphics
import DelayCore

@MainActor
enum StoreSelfTest {
    private final class MemoryStorage: StateStorage {
        var saved = StackDocument()
        var failLoad = false
        var failSave = false
        func load() throws -> StackDocument {
            if failLoad { throw NSError(domain: "QA", code: 1) }
            return saved
        }
        func save(_ value: StackDocument) throws {
            if failSave { throw NSError(domain: "QA", code: 2) }
            saved = value
        }
    }

    static func run() -> Int32 {
        var failures: [String] = []
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            checks += 1
            if !value { failures.append(message) }
        }
        let storage = MemoryStorage()
        let store = TaskStore(storage: storage)
        check(store.canEdit, "initial state editable")
        check(store.add(name: "A"), "add A")
        let a = store.tasks[0].id
        check(store.add(name: "B"), "add B")
        let b = store.tasks[0].id
        check(store.tasks.map(\.name) == ["B", "A"], "every captured task pushes to top")
        store.complete(id: a)
        check(store.tasks.map(\.name) == ["B", "A"], "lower task cannot complete")
        store.complete(id: b)
        store.complete(id: b)
        check(store.tasks.map(\.name) == ["A"], "stale repeated completion cannot pop next")
        check(store.undoName == "B", "undo available")
        _ = store.add(name: "C")
        store.undoRemoval()
        check(store.tasks.map(\.name) == ["B", "C", "A"], "undo preserves intervening addition")
        check(store.undoName == nil, "undo consumed")
        storage.failSave = true
        let prior = store.document
        check(!store.add(name: "Unsaved"), "save failure reported")
        check(store.document == prior, "save failure rolls back")
        check(store.error != nil, "save failure visible")
        store.complete(id: b)
        check(store.tasks.first?.id == b && store.undoName == nil, "failed completion offers no Undo")
        storage.failSave = false
        store.complete(id: b)
        let c = store.tasks[0].id
        store.complete(id: c)
        check(store.undoName == "C", "latest completion replaces previous Undo")
        store.undoRemoval()
        check(!store.tasks.contains(where: { $0.id == b }), "older removal is not retained in history")
        check(store.add(name: "修改 🐈"), "Unicode capture")
        let reloaded = TaskStore(storage: storage)
        check(reloaded.document == store.document && reloaded.undoName == nil, "restart restores active tasks without Undo history")
        storage.failLoad = true
        let blocked = TaskStore(storage: storage)
        check(!blocked.canEdit && blocked.error != nil, "read failure blocks overwrite and shows error")
        check(!blocked.add(name: "Overwrite"), "read failure cannot overwrite")
        storage.failLoad = false
        blocked.retryLoad()
        check(blocked.canEdit && blocked.document == storage.saved, "retry recovers")

        let stableStorage = MemoryStorage()
        let stableTask = TaskItem(name: "Existing card", color: .mint)
        stableStorage.saved.tasks = [stableTask]
        let nameOnlyStore = TaskStore(storage: stableStorage)
        check(nameOnlyStore.add(name: "New card") && stableStorage.saved.tasks.last == stableTask,
              "name-only capture preserves existing card identity and color")

        AgentStatusSelfTest.run(check: check)
        UsageSelfTest.run(check: check)
        SessionOpenSelfTest.run(check: check)

        check(TubeMetrics.width <= 224 && TubeMetrics.height + TubeMetrics.draftHeadroom <= 243,
              "upright tube and draft fit within the installed Codex pet's maximum frame")
        let screenArea = CGRect(x: -1440, y: 220, width: 1440, height: 835)
        let artworkArea = TubeMetrics.uprightArtworkArea(in: screenArea)
        let nearMenuBar = CGRect(x: artworkArea.minX, y: artworkArea.maxY - TubeMetrics.height,
                                 width: TubeMetrics.width, height: TubeMetrics.height)
        let uprightPanel = TubeMetrics.uprightPanelFrame(for: nearMenuBar)
        check(uprightPanel.origin == nearMenuBar.origin && uprightPanel.width == nearMenuBar.width
              && uprightPanel.maxY == screenArea.maxY
              && uprightPanel.height - nearMenuBar.height == TubeMetrics.draftHeadroom,
              "fixed upright headroom preserves the tube origin and fits below the menu bar")
        let display = CGRect(x: -1440, y: 180, width: 1440, height: 900)
        let usable = CGRect(x: -1400, y: 220, width: 1400, height: 835)
        let left = TuckedTubeLayout(edge: .left, expandedHeight: TubeMetrics.height,
                                    availableWidth: display.width, availableHeight: usable.height)
        let right = TuckedTubeLayout(edge: .right, expandedHeight: TubeMetrics.height,
                                     availableWidth: display.width, availableHeight: usable.height)
        let leftFrame = left.windowFrame(physical: display, visible: usable, expandedTop: display.maxY)
        let rightFrame = right.windowFrame(physical: display, visible: usable, expandedTop: display.minY)
        check(display.contains(leftFrame) && display.contains(rightFrame)
              && leftFrame.minX == display.minX && rightFrame.maxX == display.maxX
              && leftFrame.maxY <= usable.maxY && rightFrame.minY >= usable.minY,
              "tucked previews hug their display edges and avoid vertical system bars")
        let uprightSize = CGSize(width: TubeMetrics.width, height: TubeMetrics.height)
        check(leftFrame.size == uprightSize && rightFrame.size == uprightSize
              && left.artworkSize == uprightSize && right.artworkSize == uprightSize
              && left.rotation > 0 && right.rotation < 0,
              "both tilted views use the upright frame and artwork size")
        let leftBaseX = left.artworkCenter.x - CGFloat(sin(left.rotation * .pi / 180)) * left.artworkSize.height
        let rightBaseX = right.artworkCenter.x - CGFloat(sin(right.rotation * .pi / 180)) * right.artworkSize.height
        check(leftBaseX < 0 && rightBaseX > right.size.width,
              "the lower tube projects past the clip on both sides")
        let uprightAtLeft = CGRect(x: usable.minX, y: leftFrame.minY, width: uprightSize.width, height: uprightSize.height)
        let motionViewport = uprightAtLeft.union(leftFrame)
        let uprightPose = left.presentation(at: 0, upright: uprightAtLeft, tucked: leftFrame, in: motionViewport)
        let midwayPose = left.presentation(at: 0.5, upright: uprightAtLeft, tucked: leftFrame, in: motionViewport)
        let tuckedPose = left.presentation(at: 1, upright: uprightAtLeft, tucked: leftFrame, in: motionViewport)
        let pivotInViewport = CGPoint(x: midwayPose.artworkCenter.x,
                                      y: midwayPose.artworkCenter.y - uprightSize.height / 2)
        check(display.contains(motionViewport) && uprightPose.rotation == 0
              && midwayPose.rotation == left.rotation / 2 && tuckedPose.rotation == left.rotation
              && midwayPose.artworkSize == uprightSize && tuckedPose.artworkSize == uprightSize
              && midwayPose.artworkPoint(from: pivotInViewport) == CGPoint(x: uprightSize.width / 2, y: 0),
              "dock motion preserves scale and maps hits within the display-local viewport")
        let pastLeft = leftFrame.offsetBy(dx: -40, dy: 0)
        let pastRight = rightFrame.offsetBy(dx: 40, dy: 0)
        let centered = CGRect(x: usable.midX - TubeMetrics.width / 2, y: usable.midY,
                              width: TubeMetrics.width, height: TubeMetrics.height)
        check(TuckedTubeLayout.dockEdge(for: pastLeft, in: usable) == .left
              && TuckedTubeLayout.dockEdge(for: pastRight, in: usable) == .right
              && TuckedTubeLayout.dockEdge(for: centered, in: usable) == nil,
              "dragging past an edge still docks the tube on that side")

        let firstRow = CGRect(x: TubeMetrics.cardInset, y: TubeMetrics.mouthHeight + TubeMetrics.cardTopInset,
                              width: TubeMetrics.width - 2 * TubeMetrics.cardInset, height: TubeMetrics.cardHeight)
        let stride = TubeMetrics.cardHeight + TubeMetrics.cardSpacing
        let secondRow = firstRow.offsetBy(dx: 0, dy: stride)
        let scrolledRowsTop = firstRow.minY - stride
        check(TubeCardDrop.destination(at: CGPoint(x: secondRow.midX, y: secondRow.midY),
                                       height: TubeMetrics.height, rowsTop: scrolledRowsTop, count: 3) == 2,
              "local reorder retains the index of a scrolled card")
        let beforeMiddle = CGPoint(x: firstRow.midX, y: firstRow.maxY + 1)
        let afterMiddle = CGPoint(x: firstRow.midX, y: secondRow.minY - 1)
        check(TubeCardDrop.destination(at: beforeMiddle, height: TubeMetrics.height, rowsTop: scrolledRowsTop, count: 3) == 1
              && TubeCardDrop.destination(at: afterMiddle, height: TubeMetrics.height, rowsTop: scrolledRowsTop, count: 3) == 2,
              "stable insertion slots switch in the gap between rows")
        check(TubeCardDrop.destination(at: CGPoint(x: TubeMetrics.width / 2, y: TubeMetrics.mouthHeight / 2),
                                       height: TubeMetrics.height, rowsTop: scrolledRowsTop, count: 3) == 0,
              "dropping on the opening moves the card to the top")
        let outsidePoints = [CGPoint(x: -10, y: secondRow.midY),
                             CGPoint(x: TubeMetrics.width + 10, y: secondRow.midY),
                             CGPoint(x: firstRow.midX, y: TubeMetrics.height + 10)]
        check(outsidePoints.allSatisfy {
            TubeCardDrop.destination(at: $0, height: TubeMetrics.height, rowsTop: scrolledRowsTop, count: 3) == nil
        }, "releasing outside the tube cancels the reorder")

        print("Store checks: \(checks - failures.count)/\(checks) passed")
        for failure in failures { print("FAIL: \(failure)") }
        return failures.isEmpty ? 0 : 1
    }
}
