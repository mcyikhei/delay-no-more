import AppKit
import SwiftUI
import DelayCore

private struct TubeInteractiveRegion: Equatable {
    let rect: CGRect
    let clipsToInterior: Bool
    let taskID: UUID?
}

private enum FlightDirection: Equatable { case enter, exit }

private struct CardFlight {
    let id = UUID()
    let task: TaskItem
    let direction: FlightDirection
    let restingY: CGFloat
}

private struct CardDrag {
    let task: TaskItem
    let frame: CGRect
    let grabOffset: CGSize
    var center: CGPoint

    var pointer: CGPoint {
        CGPoint(x: center.x + grabOffset.width, y: center.y + grabOffset.height)
    }
}

private enum TubeScrollAnchor: Hashable { case top }

private struct TubeInteractiveRegionsKey: PreferenceKey {
    static var defaultValue: [TubeInteractiveRegion] = []
    static func reduce(value: inout [TubeInteractiveRegion], nextValue: () -> [TubeInteractiveRegion]) {
        value.append(contentsOf: nextValue())
    }
}

private extension View {
    func tubeInteractive(clipsToInterior: Bool = false, taskID: UUID? = nil) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: TubeInteractiveRegionsKey.self,
                                   value: [TubeInteractiveRegion(rect: geometry.frame(in: .named("tube")),
                                                                 clipsToInterior: clipsToInterior, taskID: taskID)])
        })
    }
}

/// Direct manipulation of the glass tube and its task cards.
struct StackView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var interaction: AppInteraction
    @ObservedObject var agentStatus: AgentStatusStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draftName = ""
    @State private var draftError: String?
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var rowsTop: CGFloat?
    @State private var flight: CardFlight?
    @State private var flightProgress: CGFloat = 0
    @State private var cardDrag: CardDrag?
    @GestureState private var dragGestureActive = false

    private var desiredHeight: CGFloat {
        min(TubeMetrics.height, interaction.maxPanelHeight)
    }

    private let headroom = TubeMetrics.draftHeadroom

    private var draftCenterY: CGFloat {
        -TubeMetrics.draftHeadroom + TubeMetrics.cardHeight / 2
    }

    private var cardWidth: CGFloat { TubeMetrics.width - 2 * TubeMetrics.cardInset }

    private var stackViewport: CGRect {
        CGRect(x: 0, y: TubeMetrics.mouthHeight, width: TubeMetrics.width,
               height: max(0, desiredHeight - TubeMetrics.mouthHeight - TubeMetrics.baseHeight))
    }

    private var topSlotCenterY: CGFloat {
        TubeMetrics.mouthHeight + TubeMetrics.cardTopInset + TubeMetrics.cardHeight / 2
    }

    private var displayedTasks: [TaskItem] {
        if let flight, flight.direction == .exit, !store.tasks.contains(where: { $0.id == flight.task.id }) {
            return [flight.task] + store.tasks
        }
        guard let drag = cardDrag, let destination = previewDestination else { return store.tasks }
        var preview = store.document
        preview.move(id: drag.task.id, to: destination)
        return preview.tasks
    }

    private var previewDestination: Int? {
        guard let cardDrag else { return nil }
        return dropDestination(at: cardDrag.pointer)
    }

    private func dropDestination(at point: CGPoint) -> Int? {
        guard let rowsTop else { return nil }
        return TubeCardDrop.destination(at: point, height: desiredHeight, rowsTop: rowsTop, count: store.tasks.count)
    }

    private var concealedTaskID: UUID? { flight?.task.id ?? cardDrag?.task.id }

    private var canActOnCards: Bool {
        store.canEdit && flight == nil && cardDrag == nil && !interaction.hasOpenEditor
    }

    var body: some View {
        TubeStatusPresentation(snapshot: agentStatus.snapshot, paused: statusAnimationsPaused) {
            stackContent
        }
    }

    private var statusAnimationsPaused: Bool {
        interaction.hasOpenEditor || interaction.draggingCard || interaction.cardFlightActive || interaction.isDocking
    }

    private var stackContent: some View {
        ZStack(alignment: .top) {
            tube.padding(.top, headroom)
            travelingCard
            TubeRim()
                .frame(height: TubeMetrics.mouthHeight)
                .mask(alignment: .bottom) { Rectangle().frame(height: TubeMetrics.mouthHeight / 2) }
                .padding(.top, headroom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if interaction.hasOpenEditor {
                draftCard
            }
        }
        .frame(width: TubeMetrics.width, height: desiredHeight + headroom)
        .clipped()
        .foregroundStyle(StackTheme.ink)
        .tint(StackTheme.accent)
        .preferredColorScheme(.light)
        .onAppear(perform: updateHeight)
        .onChange(of: desiredHeight) { _ in updateHeight() }
        .onChange(of: interaction.draggingCard) { dragging in
            if !dragging { cardDrag = nil }
        }
        .onChange(of: dragGestureActive) { active in
            if !active {
                DispatchQueue.main.async {
                    if !dragGestureActive { clearCardDrag() }
                }
            }
        }
        .task(id: flight?.id) { await animateFlight() }
        .onDisappear {
            clearCardDrag()
            finishFlight()
        }
    }

    private var tube: some View {
        ZStack {
            TubeBody().allowsHitTesting(false)
            TubeRim()
                .frame(height: TubeMetrics.mouthHeight)
                .mask(alignment: .top) { Rectangle().frame(height: TubeMetrics.mouthHeight / 2) }
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            TubeFace()
                .frame(height: TubeMetrics.baseHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                mouth
                taskStack
                Color.clear
                    .frame(height: TubeMetrics.baseHeight)
                    .allowsHitTesting(false)
            }
            TubeFront().allowsHitTesting(false)
        }
        .frame(width: TubeMetrics.width, height: desiredHeight)
        .coordinateSpace(name: "tube")
        .onPreferenceChange(TubeInteractiveRegionsKey.self, perform: updateInteractiveRegions)
    }

    private var mouth: some View {
        Color.clear
            .frame(height: TubeMetrics.mouthHeight)
            .contentShape(Ellipse())
            .onTapGesture(perform: openDraft)
            .accessibilityLabel("Add task to top")
            .accessibilityValue(agentStatus.snapshot.accessibilityDescription)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { openDraft() }
            .accessibilityHidden(!canActOnCards)
            .padding(.horizontal, TubeMetrics.wallInset)
    }

    private var draftCard: some View {
        let color = store.document.nextCardColor
        return TaskEditor(name: $draftName, onSubmit: submitDraft, onCancel: closeDraft)
            .modifier(TubeCardSurface(color: color, border: StackTheme.ink, invalid: draftError != nil))
            .frame(width: cardWidth)
            .padding(.top, headroom + draftCenterY - TubeMetrics.cardHeight / 2)
            .help(draftError ?? "Return to add. Escape to cancel.")
            .onChange(of: draftName) { _ in draftError = nil }
            .transition(.identity)
    }

    private var taskStack: some View {
        let tasks = displayedTasks
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: TubeMetrics.cardSpacing) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        TubeTaskCard(task: task, index: index, count: tasks.count,
                                     canEdit: canActOnCards,
                                     complete: { complete(task.id) },
                                     move: { destination in
                                         withAnimation(StackTheme.motion(reduced: reduceMotion)) {
                                             store.move(id: task.id, to: destination)
                                         }
                                     })
                        .id(task.id)
                        .contentShape(Rectangle())
                        .tubeInteractive(clipsToInterior: true, taskID: task.id)
                        .opacity(concealedTaskID == task.id ? 0 : 1)
                        .animation(nil, value: concealedTaskID == task.id)
                        .accessibilityHidden(concealedTaskID == task.id)
                        .transition(.identity)
                    }
                }
                .animation(StackTheme.motion(reduced: reduceMotion), value: previewDestination)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: tasks.map(\.id))
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named("tube")).minY }) { rowsTop = $0 }
                .padding(.horizontal, TubeMetrics.cardInset)
                .padding(.top, TubeMetrics.cardTopInset)
                .padding(.bottom, 10)
                .id(TubeScrollAnchor.top)
            }
            .simultaneousGesture(cardDragGesture)
            .task(id: dragScrollDirection) { await scrollWhileDragging(using: proxy) }
            .onChange(of: store.tasks.count) { count in
                guard count > 0, !interaction.draggingCard else { return }
                if flight?.direction == .enter {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo(TubeScrollAnchor.top, anchor: .top) }
                } else if flight == nil {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        proxy.scrollTo(TubeScrollAnchor.top, anchor: .top)
                    }
                }
            }
        }
    }

    private func openDraft() {
        guard canActOnCards else { return }
        draftName = ""
        draftError = nil
        interaction.hasOpenEditor = true
        interaction.beginEditing()
    }

    private func submitDraft() {
        guard interaction.hasOpenEditor, flight == nil else { return }
        guard !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reportDraftError("Enter a task name.")
            return
        }

        guard store.add(name: draftName), let task = store.tasks.first else {
            reportDraftError(store.error ?? "Couldn’t save this task. Try again.")
            return
        }
        if !reduceMotion {
            beginFlight(task: task, direction: .enter, restingY: topSlotCenterY)
        }
        closeDraft()
    }

    private func reportDraftError(_ message: String) {
        draftError = message
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func closeDraft() {
        interaction.hasOpenEditor = false
        interaction.endEditing()
    }

    private func complete(_ id: UUID) {
        guard canActOnCards, let top = store.tasks.first, top.id == id else { return }
        let restingY = cardFrames[id]?.midY ?? topSlotCenterY
        store.complete(id: id)
        if !reduceMotion, store.tasks.first?.id != id {
            beginFlight(task: top, direction: .exit, restingY: restingY)
        }
    }

    private func beginFlight(task: TaskItem, direction: FlightDirection, restingY: CGFloat) {
        flightProgress = 0
        flight = CardFlight(task: task, direction: direction, restingY: restingY)
        interaction.cardFlightActive = true
    }

    private func finishFlight() {
        guard flight != nil else { return }
        flight = nil
        flightProgress = 0
        interaction.cardFlightActive = false
    }

    private func animateFlight() async {
        guard let current = flight else { return }
        // Install the overlay at its initial position before animating it.
        do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
        guard flight?.id == current.id else { return }
        let animation: Animation = current.direction == .enter ? .easeOut(duration: 0.34) : .easeIn(duration: 0.30)
        withAnimation(animation) { flightProgress = 1 }
        do { try await Task.sleep(for: .milliseconds(current.direction == .enter ? 350 : 310)) } catch { return }
        guard flight?.id == current.id else { return }
        finishFlight()
    }

    private var travelingCard: some View {
        GeometryReader { _ in
            if let flight {
                let entering = flight.direction == .enter
                let start = entering ? draftCenterY : flight.restingY
                let end = entering ? flight.restingY : -headroom - TubeMetrics.cardHeight / 2 - 2
                FlyingCard(task: flight.task, progress: flightProgress, entering: entering,
                           startY: headroom + start, endY: headroom + end, width: cardWidth)
                    .transition(.identity)
            } else if let cardDrag {
                TubeCardFace(task: cardDrag.task)
                    .frame(width: cardDrag.frame.width)
                    .position(cardDrag.center)
                    .frame(width: TubeMetrics.width, height: desiredHeight)
                    .clipped()
                    .padding(.top, headroom)
                    .transition(.identity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var cardDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("tube"))
            .updating($dragGestureActive) { _, active, _ in active = true }
            .onChanged(updateCardDrag)
            .onEnded { value in commitCardDrag(at: value.location) }
    }

    private func updateCardDrag(_ value: DragGesture.Value) {
        guard store.canEdit, flight == nil, !interaction.hasOpenEditor else { return }
        if var drag = cardDrag {
            drag.center = CGPoint(x: value.location.x - drag.grabOffset.width,
                                  y: value.location.y - drag.grabOffset.height)
            cardDrag = drag
            return
        }
        guard let task = store.tasks.first(where: {
            cardFrames[$0.id]?.intersection(stackViewport).contains(value.startLocation) == true
        }), let frame = cardFrames[task.id] else { return }
        let offset = CGSize(width: value.startLocation.x - frame.midX, height: value.startLocation.y - frame.midY)
        cardDrag = CardDrag(task: task, frame: frame, grabOffset: offset,
                            center: CGPoint(x: value.location.x - offset.width, y: value.location.y - offset.height))
        interaction.draggingCard = true
    }

    private func commitCardDrag(at point: CGPoint) {
        guard let drag = cardDrag else { return }
        let destination = dropDestination(at: point)
        withAnimation(StackTheme.motion(reduced: reduceMotion)) {
            if let destination { store.move(id: drag.task.id, to: destination) }
            clearCardDrag()
        }
    }

    private func clearCardDrag() {
        cardDrag = nil
        if interaction.draggingCard { interaction.draggingCard = false }
    }

    private var dragScrollDirection: Int {
        guard let cardDrag else { return 0 }
        let x = cardDrag.pointer.x
        let y = cardDrag.pointer.y
        guard x >= TubeMetrics.wallInset, x <= TubeMetrics.width - TubeMetrics.wallInset,
              y >= stackViewport.minY, y < stackViewport.maxY else { return 0 }
        if y < stackViewport.minY + 16 { return -1 }
        if y > stackViewport.maxY - 16 { return 1 }
        return 0
    }

    private func scrollWhileDragging(using proxy: ScrollViewProxy) async {
        let direction = dragScrollDirection
        guard direction != 0 else { return }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard dragScrollDirection == direction else { return }
            let tasks = displayedTasks
            let visible = tasks.indices.filter { index in
                cardFrames[tasks[index].id]?.intersects(stackViewport) == true
            }
            guard let edge = direction < 0 ? visible.first : visible.last else { return }
            let target = edge + direction
            guard tasks.indices.contains(target) else { continue }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                proxy.scrollTo(tasks[target].id, anchor: direction < 0 ? .top : .bottom)
            }
        }
    }

    private func updateHeight() {
        if interaction.preferredHeight != desiredHeight { interaction.preferredHeight = desiredHeight }
    }

    private func updateInteractiveRegions(_ regions: [TubeInteractiveRegion]) {
        let whole = CGRect(x: 0, y: 0, width: TubeMetrics.width, height: desiredHeight)
        var rectangles: [CGRect] = []
        var frames: [UUID: CGRect] = [:]
        for region in regions {
            let rect = region.rect.intersection(region.clipsToInterior ? stackViewport : whole)
            guard !rect.isNull, !rect.isEmpty else { continue }
            rectangles.append(rect)
            if let id = region.taskID { frames[id] = region.rect }
        }
        if cardFrames != frames { cardFrames = frames }
        if interaction.dragExclusions != rectangles { interaction.dragExclusions = rectangles }
    }
}

private struct FlyingCard: View, Animatable {
    let task: TaskItem
    var progress: CGFloat
    let entering: Bool
    let startY: CGFloat
    let endY: CGFloat
    let width: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let tilt = entering ? -40 * sin(Double(progress) * .pi) : 45 * Double(progress)
        TubeCardFace(task: task)
            .frame(width: width)
            .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .position(x: TubeMetrics.width / 2, y: startY + (endY - startY) * progress)
    }
}

private struct TubeTaskCard: View {
    let task: TaskItem
    let index: Int
    let count: Int
    let canEdit: Bool
    let complete: () -> Void
    let move: (Int) -> Void

    var body: some View {
        TubeCardFace(task: task, scrollsOnHover: canEdit)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                if index == 0 && canEdit { complete() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(index == 0 ? "Next task" : "Task \(index + 1)")
            .accessibilityActions {
                if canEdit {
                    if index == 0 { Button("Complete task", action: complete) }
                    if index > 0 {
                        Button("Move up") { move(index - 1) }
                        Button("Move to top") { move(0) }
                    }
                    if index < count - 1 {
                        Button("Move down") { move(index + 1) }
                        Button("Move to bottom") { move(count - 1) }
                    }
                }
            }
    }
}
