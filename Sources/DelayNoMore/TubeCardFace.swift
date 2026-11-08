import AppKit
import SwiftUI
import DelayCore

/// Shared artwork for interactive rows, moving cards and the tucked preview.
struct TubeCardFace: View {
    let task: TaskItem
    var scrollsOnHover = false

    private var title: Text {
        Text(task.name).font(.system(size: 12, weight: .medium, design: .rounded))
    }

    var body: some View {
        if scrollsOnHover {
            HoveringCardTitle(title: title, name: task.name, color: task.color)
        } else {
            title.lineLimit(1).modifier(TubeCardSurface(color: task.color))
        }
    }
}

private struct HoveringCardTitle: View {
    let title: Text
    let name: String
    let color: CardColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var titleWidth: CGFloat = 0
    @State private var isHovered = false
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { viewport in
            let overflow = max(0, titleWidth - viewport.size.width)
            let scrolling = overflow > 0.5 && isHovered && !reduceMotion
            Group {
                if scrolling {
                    fullTitle.offset(x: -offset)
                } else {
                    title.lineLimit(1)
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .leading)
            .clipped()
            .help(reduceMotion ? name : "")
            .task(id: scrolling ? overflow : 0) {
                await scrollTitle(by: scrolling ? overflow : 0)
            }
        }
        .background(alignment: .leading) {
            fullTitle
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { titleWidth = $0 }
                .hidden()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .modifier(TubeCardSurface(color: color))
        .background {
            CardHoverArea { isHovered = $0 }
        }
    }

    private var fullTitle: some View {
        title.lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }

    private func scrollTitle(by distance: CGFloat) async {
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) { offset = 0 }
        guard distance > 0 else { return }

        let travel = max(0.35, Double(distance) / 32)
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(450))
                withAnimation(.linear(duration: travel)) { offset = distance }
                try await Task.sleep(for: .seconds(travel + 0.75))
                withAnimation(.linear(duration: travel)) { offset = 0 }
                try await Task.sleep(for: .seconds(travel))
            } catch {
                return
            }
        }
    }
}

/// The floating panel normally has no keyboard focus, so track hover in any app.
private struct CardHoverArea: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView { TrackingView() }

    func updateNSView(_ view: TrackingView, context: Context) { view.onHover = onHover }

    final class TrackingView: NSView {
        var onHover: (Bool) -> Void = { _ in }
        private var hoverArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverArea = area
        }

        override func mouseEntered(with event: NSEvent) { onHover(true) }
        override func mouseExited(with event: NSEvent) { onHover(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

struct TubeCardSurface: ViewModifier {
    let color: CardColor
    var border: Color = .white.opacity(0.72)
    var invalid = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: StackTheme.cardRadius)
        let fill = StackTheme.cardFill(color)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .frame(height: TubeMetrics.cardHeight)
            .foregroundStyle(StackTheme.ink)
            .background(fill)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: invalid ? [3, 2] : []))
                    .allowsHitTesting(false)
            }
            .background {
                shape.fill(fill.shadow(.inner(color: StackTheme.ink.opacity(0.12), radius: 2, y: -1)))
                    .offset(y: 2)
            }
            .shadow(color: StackTheme.ink.opacity(0.1), radius: 2, x: 0, y: 2)
    }
}
