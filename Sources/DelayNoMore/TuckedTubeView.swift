import SwiftUI
import DelayCore

/// Rotate the art within a clip that stays on the selected display.
struct TuckedTubeLayout {
    private let edge: DockEdge
    let artworkSize: CGSize
    let size: CGSize
    let artworkCenter: CGPoint
    let rotation: Double

    static func dockEdge(for frame: CGRect, in visible: CGRect) -> DockEdge? {
        let leftGap = frame.minX - visible.minX
        let rightGap = visible.maxX - frame.maxX
        guard min(leftGap, rightGap) <= 20 else { return nil }
        return leftGap <= rightGap ? .left : .right
    }

    init(edge: DockEdge, expandedHeight: CGFloat, availableWidth: CGFloat, availableHeight: CGFloat) {
        self.edge = edge
        let angle = 36.0
        let radians = angle * .pi / 180
        let sine = CGFloat(sin(radians))
        let cosine = CGFloat(cos(radians))
        let width = TubeMetrics.width
        let mouthHalfWidth = (width - 2 * TubeMetrics.wallInset) / 2
        let mouthHalfHeight = TubeMetrics.mouthHeight / 2
        let projectedHalfWidth = hypot(mouthHalfWidth * cosine, mouthHalfHeight * sine)
        let projectedHalfHeight = hypot(mouthHalfWidth * sine, mouthHalfHeight * cosine)
        let glowPadding: CGFloat = 4

        // Keep the full-size artwork and window. Place the opening next to the
        // edge so the tilt carries the lower wall outside the display clip.
        let previewWidth = max(1, min(width, availableWidth))
        let previewHeight = max(1, min(expandedHeight, availableHeight))
        let mouthEdgeDistance = min(previewWidth / 2, projectedHalfWidth + glowPadding)
        let mouthCenterX = edge == .right ? previewWidth - mouthEdgeDistance : mouthEdgeDistance
        let artworkTop = max(0, projectedHalfHeight + glowPadding - mouthHalfHeight * cosine)
        let direction: CGFloat = edge == .right ? 1 : -1

        artworkSize = CGSize(width: width, height: expandedHeight)
        size = CGSize(width: previewWidth, height: previewHeight)
        artworkCenter = CGPoint(x: mouthCenterX - direction * mouthHalfHeight * sine,
                                y: artworkTop + expandedHeight / 2)
        rotation = edge == .right ? -angle : angle
    }

    func windowFrame(physical: CGRect, visible: CGRect, expandedTop: CGFloat) -> CGRect {
        let x = edge == .left ? physical.minX : physical.maxX - size.width
        let top = max(visible.minY + size.height, min(expandedTop, visible.maxY))
        return CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    var presentation: TubeDockPresentation {
        TubeDockPresentation(size: size, artworkSize: artworkSize,
                             artworkCenter: artworkCenter, rotation: rotation)
    }

    func presentation(at progress: CGFloat, upright: CGRect, tucked: CGRect,
                      in viewport: CGRect) -> TubeDockPresentation {
        let uprightCenter = CGPoint(x: upright.midX - viewport.minX,
                                    y: viewport.maxY - upright.midY)
        let tuckedCenter = CGPoint(x: tucked.minX - viewport.minX + artworkCenter.x,
                                   y: viewport.maxY - tucked.maxY + artworkCenter.y)
        let center = CGPoint(x: uprightCenter.x + (tuckedCenter.x - uprightCenter.x) * progress,
                             y: uprightCenter.y + (tuckedCenter.y - uprightCenter.y) * progress)
        return TubeDockPresentation(size: viewport.size, artworkSize: artworkSize,
                                   artworkCenter: center, rotation: rotation * Double(progress))
    }
}

struct TubeDockPresentation {
    let size: CGSize
    let artworkSize: CGSize
    let artworkCenter: CGPoint
    let rotation: Double

    func artworkPoint(from previewPoint: CGPoint) -> CGPoint {
        let radians = rotation * .pi / 180
        let sine = CGFloat(sin(radians))
        let cosine = CGFloat(cos(radians))
        let x = previewPoint.x - artworkCenter.x
        let y = previewPoint.y - (artworkCenter.y - artworkSize.height / 2)
        return CGPoint(x: artworkSize.width / 2 + x * cosine + y * sine,
                       y: -x * sine + y * cosine)
    }
}

struct TuckedTubeView: View {
    let presentation: TubeDockPresentation
    let tasks: [TaskItem]
    @ObservedObject var agentStatus: AgentStatusStore
    @ObservedObject var interaction: AppInteraction
    @ObservedObject var usage: AgentUsageStore

    private var statusAnimationsPaused: Bool { interaction.isDocking }

    var body: some View {
        TubeStatusPresentation(snapshot: agentStatus.snapshot, paused: statusAnimationsPaused) {
            preview
        }
    }

    private var preview: some View {
        ZStack {
            ZStack {
                TubeBody()
                TubeWater(fraction: usage.fraction)
                TubeRim()
                    .frame(height: TubeMetrics.mouthHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                TubeFace()
                    .frame(height: TubeMetrics.baseHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                cards
                TubeFront()
            }
            .frame(width: presentation.artworkSize.width, height: presentation.artworkSize.height)
            .rotationEffect(.degrees(presentation.rotation), anchor: .top)
            .position(presentation.artworkCenter)
        }
        .frame(width: presentation.size.width, height: presentation.size.height)
        .clipped()
        .foregroundStyle(StackTheme.ink)
        .preferredColorScheme(.light)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var cards: some View {
        let interiorHeight = max(0, presentation.artworkSize.height - TubeMetrics.mouthHeight - TubeMetrics.baseHeight)
        let rowStride = TubeMetrics.cardHeight + TubeMetrics.cardSpacing
        let rowCount = Int(ceil(max(0, interiorHeight - TubeMetrics.cardTopInset) / rowStride))
        let cardWidth = presentation.artworkSize.width - 2 * TubeMetrics.cardInset

        return VStack(spacing: 0) {
            Color.clear.frame(height: TubeMetrics.mouthHeight)
            VStack(spacing: TubeMetrics.cardSpacing) {
                ForEach(tasks.prefix(rowCount)) { task in
                    TubeCardFace(task: task)
                        .frame(width: cardWidth, height: TubeMetrics.cardHeight)
                }
            }
            .padding(.top, TubeMetrics.cardTopInset)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: presentation.artworkSize.width, height: interiorHeight, alignment: .top)
            .clipped()
            Spacer(minLength: 0)
        }
        .frame(width: presentation.artworkSize.width, height: presentation.artworkSize.height, alignment: .top)
    }
}
