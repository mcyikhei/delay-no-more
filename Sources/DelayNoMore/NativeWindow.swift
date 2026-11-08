import AppKit
import Combine
import SwiftUI
import DelayCore

/// The panel takes typing focus only after an explicit Add or Edit action.
@MainActor
final class StackPanel: NSPanel {
    var keyboardRequested = false
    var prepareForTextInput: ((NSEvent) -> Void)?
    var canStartPetDrag: ((NSEvent) -> Bool)?
    var dragStarted: (() -> Void)?
    var dragFinished: ((Bool) -> Void)?
    private var petDrag: PetWindowDrag?
    private var suppressingSecondaryClick = false

    override var canBecomeKey: Bool { keyboardRequested }
    override var canBecomeMain: Bool { false }

    func finishPetDrag() {
        guard let drag = petDrag else { return }
        petDrag = nil
        if drag.hasMoved { NSCursor.pop() }
        dragFinished?(drag.hasMoved)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            finishPetDrag()
            suppressingSecondaryClick = event.modifierFlags.contains(.control)
            if suppressingSecondaryClick { return }
            if canStartPetDrag?(event) == true {
                petDrag = PetWindowDrag(pointer: convertPoint(toScreen: event.locationInWindow),
                                        windowOrigin: frame.origin)
                dragStarted?()
                return
            }
            if !isKeyWindow { prepareForTextInput?(event) }
        case .leftMouseDragged:
            if suppressingSecondaryClick { return }
            if var drag = petDrag {
                let wasMoving = drag.hasMoved
                if let origin = drag.move(to: NSEvent.mouseLocation) {
                    if !wasMoving { NSCursor.closedHand.push() }
                    setFrameOrigin(origin)
                }
                petDrag = drag
                return
            }
        case .leftMouseUp:
            if suppressingSecondaryClick {
                suppressingSecondaryClick = false
                return
            }
            if petDrag != nil {
                finishPetDrag()
                return
            }
        case .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            return
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyboardRequested,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers?.lowercased() {
            let action: Selector?
            switch key {
            case "a": action = #selector(NSText.selectAll(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "v": action = #selector(NSText.paste(_:))
            case "x": action = #selector(NSText.cut(_:))
            case "z": action = Selector(("undo:"))
            default: action = nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class StackWindowController: NSObject, NSWindowDelegate {
    private struct DockMotion {
        let layout: TuckedTubeLayout
        let upright: CGRect
        let tucked: CGRect
        let viewport: CGRect
        var progress: CGFloat

        var presentation: TubeDockPresentation {
            layout.presentation(at: progress, upright: upright, tucked: tucked, in: viewport)
        }
    }

    private let store: TaskStore
    private let interaction: AppInteraction
    private let agentStatus: AgentStatusStore
    private let usage: AgentUsageStore
    private let panel: StackPanel
    private let stackHostingView: ClearHostingView<StackView>
    private let expandedContainer = HoverContainerView()
    private let tuckedHitView = TuckedTubeHitView()
    private var tuckedHostingView: ClearHostingView<TuckedTubeView>?
    private var subscriptions = Set<AnyCancellable>()
    private var hideTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var cardReleaseTask: Task<Void, Never>?
    private var dockMotionTask: Task<Void, Never>?
    private var dockMotion: DockMotion?
    private var expandedFrame = NSRect(x: 0, y: 0, width: TubeMetrics.width, height: TubeMetrics.height)
    private var dockEdge: DockEdge?
    private var isDraggingWindow = false
    private var menuTracking = false
    private var isExplicitlyHidden = false
    private var chosenScreenID: UInt32?

    init(store: TaskStore, interaction: AppInteraction, agentStatus: AgentStatusStore, usage: AgentUsageStore) {
        self.store = store
        self.interaction = interaction
        self.agentStatus = agentStatus
        self.usage = usage
        stackHostingView = ClearHostingView(rootView: StackView(store: store, interaction: interaction, agentStatus: agentStatus, usage: usage))
        panel = StackPanel(contentRect: TubeMetrics.uprightPanelFrame(for: expandedFrame),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        super.init()

        panel.title = "Delay No More"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.delegate = self
        panel.animationBehavior = .none

        for view in [expandedContainer, stackHostingView, tuckedHitView] as [NSView] {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
        }
        tuckedHitView.layer?.masksToBounds = true
        stackHostingView.sizingOptions = []
        stackHostingView.frame = expandedContainer.bounds
        stackHostingView.autoresizingMask = [.width, .height]
        expandedContainer.addSubview(stackHostingView)

        expandedContainer.hovered = { [weak self] in self?.agentStatus.acknowledgeCompletion() }
        tuckedHitView.hovered = { [weak self] in self?.agentStatus.acknowledgeCompletion() }
        expandedContainer.entered = { [weak self] in self?.cancelHide() }
        expandedContainer.exited = { [weak self] in self?.scheduleTuck() }
        tuckedHitView.entered = { [weak self] in self?.scheduleReveal() }
        tuckedHitView.exited = { [weak self] in self?.revealTask?.cancel() }
        tuckedHitView.reveal = { [weak self] in self?.show() }
        panel.canStartPetDrag = { [weak self] event in self?.canStartPetDrag(with: event) ?? false }
        panel.dragStarted = { [weak self] in
            self?.isDraggingWindow = true
            self?.cancelHide()
        }
        panel.dragFinished = { [weak self] moved in
            guard let self else { return }
            self.isDraggingWindow = false
            if moved { self.finishedWindowDrag() }
            else { self.scheduleTuck() }
        }
        panel.prepareForTextInput = { [weak self] event in self?.resumeDraftInput(with: event) }

        interaction.requestKeyboard = { [weak self] in self?.requestKeyboard() }
        interaction.finishEditing = { [weak self] in self?.finishEditing() }

        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuBegan),
                                               name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded),
                                               name: NSMenu.didEndTrackingNotification, object: nil)

        restorePlacement()
        panel.contentView = expandedContainer
        panel.setFrame(uprightPanelFrame, display: true)

        interaction.$preferredHeight.removeDuplicates().sink { [weak self] height in
            self?.resizeExpanded(to: height)
        }.store(in: &subscriptions)
        store.$document.sink { [weak self] document in
            guard let self else { return }
            if let presentation = self.tuckedHitView.presentation {
                self.tuckedHostingView?.rootView = TuckedTubeView(presentation: presentation, tasks: document.tasks,
                                                               agentStatus: self.agentStatus,
                                                               interaction: self.interaction, usage: self.usage)
            }
            self.writeDiagnostics(taskCount: document.tasks.count)
        }.store(in: &subscriptions)
        agentStatus.$snapshot.removeDuplicates().sink { [weak self] snapshot in
            self?.tuckedHitView.setAccessibilityValue(snapshot.accessibilityDescription)
        }.store(in: &subscriptions)
        interaction.$isEditing.dropFirst().sink { [weak self] _ in self?.writeDiagnostics() }.store(in: &subscriptions)
        interaction.$hasOpenEditor.removeDuplicates().sink { [weak self] isOpen in
            self?.expandedContainer.acceptsDraftHit = isOpen
        }.store(in: &subscriptions)
        interaction.$draggingCard.removeDuplicates().sink { [weak self] dragging in
            self?.watchCardRelease(when: dragging)
        }.store(in: &subscriptions)
        interaction.$cardFlightActive.removeDuplicates().sink { [weak self] active in
            if active { self?.cancelHide() }
            else { self?.scheduleTuck() }
        }.store(in: &subscriptions)
    }

    /// Only this panel's background starts a pet drag. SwiftUI keeps the original
    /// event for the mouth, task cards, editors, and the base's actual controls.
    private func canStartPetDrag(with event: NSEvent) -> Bool {
        guard panel.isVisible, !interaction.tucked,
              !interaction.draggingCard, !interaction.cardFlightActive, !isDraggingWindow, !menuTracking,
              !interaction.hasOpenEditor,
              !isExplicitlyHidden, let content = panel.contentView,
              content === expandedContainer else { return false }
        let local = content.convert(event.locationInWindow, from: nil)
        guard expandedContainer.containsTubeInteraction(at: local) else { return false }
        let point = expandedContainer.artworkPoint(at: local)
        let bounds = CGRect(origin: .zero, size: expandedContainer.artworkSize)
        let mouth = CGRect(x: TubeMetrics.wallInset, y: 0,
                           width: TubeMetrics.width - 2 * TubeMetrics.wallInset,
                           height: TubeMetrics.mouthHeight)
        return PetHitRegions.isBackgroundDrag(at: point, in: bounds, mouth: mouth,
                                               protectedRects: interaction.dragExclusions)
    }

    func show() {
        revealTask?.cancel()
        cancelHide()
        isExplicitlyHidden = false
        if panel.isVisible, interaction.tucked, let edge = dockEdge, let screen = screen(with: chosenScreenID),
           beginDockMotion(towardTucked: false, edge: edge, screen: screen) { return }
        if panel.isVisible, dockMotion != nil, !interaction.tucked { return }
        installUpright()
        panel.orderFrontRegardless()
        scheduleTuck()
        writeDiagnostics()
    }

    private var uprightPanelFrame: CGRect {
        TubeMetrics.uprightPanelFrame(for: expandedFrame)
    }

    private func installUpright() {
        cancelDockMotion()
        interaction.tucked = false
        panel.contentView = expandedContainer
        panel.acceptsMouseMovedEvents = true
        tuckedHitView.resetHover()
        tuckedHitView.presentation = nil
        tuckedHostingView?.removeFromSuperview()
        tuckedHostingView = nil
        panel.setFrame(uprightPanelFrame, display: true)
    }

    func hide() {
        panel.finishPetDrag()
        cancelHide()
        revealTask?.cancel()
        isExplicitlyHidden = true
        panel.orderOut(nil)
        installUpright()
        writeDiagnostics()
    }

    private func requestKeyboard() {
        cancelHide()
        if interaction.tucked || dockMotion != nil || !panel.isVisible {
            isExplicitlyHidden = false
            installUpright()
        }
        panel.keyboardRequested = true
        panel.makeKeyAndOrderFront(nil)
        writeDiagnostics()
    }

    private func resumeDraftInput(with event: NSEvent) {
        guard panel.contentView === expandedContainer else { return }
        let local = expandedContainer.convert(event.locationInWindow, from: nil)
        if expandedContainer.containsDraftInteraction(at: local) { interaction.beginEditing() }
    }

    private func finishEditing() {
        panel.resignKey()
        panel.keyboardRequested = false
        scheduleTuck()
        writeDiagnostics()
    }

    private func screen(with id: UInt32?) -> NSScreen? {
        NSScreen.screens.first(where: { displayID($0) == id }) ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func displayID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func restorePlacement() {
        let placement = store.windowPlacement
        dockEdge = placement.dockEdge
        guard let screen = screen(with: placement.screenID) else { return }
        chosenScreenID = displayID(screen)
        updateHeightLimit(screen)
        let height = min(TubeMetrics.height, interaction.maxPanelHeight)
        let visible = screen.visibleFrame
        let x = placement.x.map { CGFloat($0) } ?? visible.maxX - TubeMetrics.width - 24
        let top = placement.y.map { CGFloat($0) } ?? visible.maxY - 64
        expandedFrame.origin.x = x
        positionArtwork(top: top, height: height, in: visible)
    }

    private func updateHeightLimit(_ screen: NSScreen) {
        let artworkArea = TubeMetrics.uprightArtworkArea(in: screen.visibleFrame)
        interaction.maxPanelHeight = max(1, min(TubeMetrics.height, artworkArea.height))
    }

    private func clamped(_ frame: NSRect, to visible: NSRect) -> NSRect {
        var result = frame
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.minY, visible.minY), visible.maxY - result.height)
        return result
    }

    private func applyDockPosition(in visible: NSRect) {
        if dockEdge == .left { expandedFrame.origin.x = visible.minX }
        if dockEdge == .right { expandedFrame.origin.x = visible.maxX - expandedFrame.width }
    }

    private func positionArtwork(top: CGFloat, height: CGFloat, in visible: CGRect) {
        expandedFrame.size.height = height
        expandedFrame.origin.y = top - height
        expandedFrame = clamped(expandedFrame, to: TubeMetrics.uprightArtworkArea(in: visible))
        applyDockPosition(in: visible)
    }

    private func resizeExpanded(to requestedHeight: CGFloat) {
        guard let screen = screen(with: chosenScreenID) else { return }
        let height = max(1, min(TubeMetrics.height, requestedHeight, interaction.maxPanelHeight))
        guard height != expandedFrame.height else { return }
        positionArtwork(top: expandedFrame.maxY, height: height, in: screen.visibleFrame)
        cancelDockMotion()
        if interaction.tucked, let edge = dockEdge {
            installTuckedPreview(edge: edge, screen: screen)
        } else {
            installUpright()
            scheduleTuck()
        }
        writeDiagnostics()
    }

    private func finishedWindowDrag() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        chosenScreenID = displayID(screen)
        updateHeightLimit(screen)
        var frame = panel.frame
        frame.size.height = max(1, frame.height - TubeMetrics.draftHeadroom)
        let visible = screen.visibleFrame
        dockEdge = TuckedTubeLayout.dockEdge(for: frame, in: visible)
        expandedFrame = clamped(frame, to: TubeMetrics.uprightArtworkArea(in: visible))
        applyDockPosition(in: visible)
        panel.setFrame(uprightPanelFrame, display: true)
        persistPlacement()
        scheduleTuck()
    }

    private func persistPlacement() {
        store.savePlacement(WindowPlacement(x: Double(expandedFrame.minX),
                                            y: Double(expandedFrame.maxY),
                                            screenID: chosenScreenID, dockEdge: dockEdge))
        writeDiagnostics()
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func pointerIsInsideArtwork() -> Bool { expandedFrame.contains(NSEvent.mouseLocation) }

    private func pointerIsOverTuckedArtwork() -> Bool {
        let pointer = NSEvent.mouseLocation
        guard panel.frame.contains(pointer) else { return false }
        let windowPoint = panel.convertPoint(fromScreen: pointer)
        return tuckedHitView.containsArtwork(at: tuckedHitView.convert(windowPoint, from: nil))
    }

    private func refreshTuckedHover() {
        guard panel.isVisible, !isExplicitlyHidden else { return }
        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        tuckedHitView.updateHover(at: tuckedHitView.convert(windowPoint, from: nil))
    }

    private func scheduleReveal() {
        revealTask?.cancel()
        revealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, self.interaction.tucked,
                  self.pointerIsOverTuckedArtwork() else { return }
            self.show()
        }
    }

    private func watchCardRelease(when dragging: Bool) {
        cardReleaseTask?.cancel()
        guard dragging else { scheduleTuck(); return }
        cancelHide()
        cardReleaseTask = Task { @MainActor [weak self] in
            repeat { try? await Task.sleep(for: .milliseconds(50)) }
            while !Task.isCancelled && NSEvent.pressedMouseButtons & 1 != 0
            // Give the card gesture time to process release before clearing it.
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            self.interaction.draggingCard = false
            self.scheduleTuck()
        }
    }

    private func scheduleTuck() {
        cancelHide()
        guard dockEdge != nil, !interaction.tucked, !isExplicitlyHidden, dockMotion == nil else { return }
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            self.tuckIfPossible()
        }
    }

    private func tuckIfPossible() {
        guard panel.isVisible, let edge = dockEdge, !interaction.isEditing, !interaction.hasOpenEditor,
              dockMotion == nil, !interaction.draggingCard,
              !interaction.cardFlightActive, !isDraggingWindow, !menuTracking, !panel.isKeyWindow,
              !pointerIsInsideArtwork(), !isExplicitlyHidden,
              let screen = screen(with: chosenScreenID) else { return }
        revealTask?.cancel()
        if beginDockMotion(towardTucked: true, edge: edge, screen: screen) { return }
        interaction.tucked = true
        installTuckedPreview(edge: edge, screen: screen)
        writeDiagnostics()
    }

    private func tuckedLayout(edge: DockEdge, screen: NSScreen) -> (layout: TuckedTubeLayout, frame: CGRect) {
        let physical = screen.frame
        let visible = screen.visibleFrame
        let layout = TuckedTubeLayout(edge: edge, expandedHeight: expandedFrame.height,
                                      availableWidth: physical.width, availableHeight: visible.height)
        return (layout, layout.windowFrame(physical: physical, visible: visible, expandedTop: expandedFrame.maxY))
    }

    private func installTuckedPreview(edge: DockEdge, screen: NSScreen) {
        let tucked = tuckedLayout(edge: edge, screen: screen)
        renderDockPresentation(tucked.layout.presentation, frame: tucked.frame)
    }

    private func renderDockPresentation(_ presentation: TubeDockPresentation, frame: CGRect? = nil) {
        let preview = TuckedTubeView(presentation: presentation, tasks: store.tasks,
                                    agentStatus: agentStatus, interaction: interaction, usage: usage)
        tuckedHitView.presentation = presentation
        if let tuckedHostingView {
            tuckedHostingView.rootView = preview
        } else {
            let hostingView = ClearHostingView(rootView: preview)
            hostingView.sizingOptions = []
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.frame = tuckedHitView.bounds
            hostingView.autoresizingMask = [.width, .height]
            tuckedHitView.addSubview(hostingView)
            tuckedHostingView = hostingView
        }
        if let frame {
            if panel.contentView !== tuckedHitView { panel.contentView = tuckedHitView }
            panel.acceptsMouseMovedEvents = true
            panel.setFrame(frame, display: true)
        }
        refreshTuckedHover()
    }

    private func beginDockMotion(towardTucked: Bool, edge: DockEdge, screen: NSScreen) -> Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return false }
        let motion: DockMotion
        if let dockMotion {
            motion = dockMotion
        } else {
            let tucked = tuckedLayout(edge: edge, screen: screen)
            let viewport = expandedFrame.union(tucked.frame).intersection(screen.frame)
            guard !viewport.isNull, !viewport.isEmpty else { return false }
            motion = DockMotion(layout: tucked.layout, upright: expandedFrame, tucked: tucked.frame,
                                viewport: viewport, progress: interaction.tucked ? 1 : 0)
        }
        let target: CGFloat = towardTucked ? 1 : 0
        guard motion.progress != target else { return false }

        dockMotionTask?.cancel()
        dockMotion = motion
        interaction.isDocking = true
        interaction.tucked = towardTucked
        renderDockPresentation(motion.presentation, frame: motion.viewport)
        writeDiagnostics()

        let started = ProcessInfo.processInfo.systemUptime
        let duration = max(0.07, 0.28 * Double(abs(target - motion.progress)))
        dockMotionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                let fraction = CGFloat(min(1, elapsed / duration))
                if fraction >= 1 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    self.finishDockMotion(motion, tucked: towardTucked)
                    return
                }
                let eased = fraction * fraction * (3 - 2 * fraction)
                var current = motion
                current.progress += (target - motion.progress) * eased
                self.dockMotion = current
                self.renderDockPresentation(current.presentation)
                do { try await Task.sleep(for: .milliseconds(16)) }
                catch { return }
            }
        }
        return true
    }

    private func finishDockMotion(_ motion: DockMotion, tucked: Bool) {
        cancelDockMotion()
        if tucked {
            renderDockPresentation(motion.layout.presentation, frame: motion.tucked)
        } else {
            installUpright()
            scheduleTuck()
        }
        writeDiagnostics()
    }

    private func cancelDockMotion() {
        dockMotionTask?.cancel()
        dockMotionTask = nil
        dockMotion = nil
        interaction.isDocking = false
    }

    @objc private func menuBegan() { menuTracking = true; cancelHide() }
    @objc private func menuEnded() { menuTracking = false; scheduleTuck() }

    @objc private func screenConfigurationChanged() {
        guard let screen = screen(with: chosenScreenID) else { return }
        chosenScreenID = displayID(screen)
        cancelDockMotion()
        revealTask?.cancel()
        tuckedHitView.resetHover()
        updateHeightLimit(screen)
        positionArtwork(top: expandedFrame.maxY,
                        height: interaction.maxPanelHeight, in: screen.visibleFrame)
        if interaction.tucked, let edge = dockEdge {
            installTuckedPreview(edge: edge, screen: screen)
        } else {
            installUpright()
            scheduleTuck()
        }
        persistPlacement()
    }

    func windowDidResignKey(_ notification: Notification) {
        if !interaction.hasOpenEditor {
            interaction.isEditing = false
            panel.keyboardRequested = false
        }
        scheduleTuck()
        writeDiagnostics()
    }
    func windowDidBecomeKey(_ notification: Notification) { cancelHide(); writeDiagnostics() }

    /// Opt-in diagnostics for native QA; contains geometry and state, never task text.
    private func writeDiagnostics(taskCount: Int? = nil) {
        guard let path = ProcessInfo.processInfo.environment["DELAY_NO_MORE_DIAGNOSTICS"] else { return }
        let info: [String: Any] = [
            "tucked": interaction.tucked,
            "visible": panel.isVisible,
            "key": panel.isKeyWindow,
            "editing": interaction.isEditing,
            "dockEdge": dockEdge.map { $0 == .left ? "left" : "right" } ?? "none",
            "x": panel.frame.minX, "y": panel.frame.minY,
            "width": panel.frame.width, "height": panel.frame.height,
            "taskCount": taskCount ?? store.tasks.count
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}
