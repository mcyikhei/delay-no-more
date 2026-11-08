import AppKit
import SwiftUI
import DelayCore

// Pet hit-testing and hover views hosted by StackWindowController.

@MainActor
final class HoverContainerView: NSView {
    var hovered: (() -> Void)?
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    var acceptsDraftHit = false
    private var hoverArea: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard containsTubeInteraction(at: local) || containsDraftInteraction(at: local) else { return nil }
        return super.hitTest(point)
    }

    /// Match the glass walls and curved ends; empty window margins are not pet.
    func containsTubeInteraction(at point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        return TubeHitShape.contains(artworkPoint(at: point), size: artworkSize)
    }

    func containsDraftInteraction(at point: NSPoint) -> Bool {
        guard acceptsDraftHit, bounds.contains(point) else { return false }
        let topDown = PetHitRegions.topDownPoint(point, in: bounds, isFlipped: isFlipped)
        let draft = CGRect(x: TubeMetrics.cardInset, y: 0,
                           width: bounds.width - 2 * TubeMetrics.cardInset, height: TubeMetrics.cardHeight)
        return draft.contains(topDown)
    }

    var artworkSize: CGSize {
        CGSize(width: bounds.width, height: max(0, bounds.height - TubeMetrics.draftHeadroom))
    }

    func artworkPoint(at point: NSPoint) -> CGPoint {
        var topDown = PetHitRegions.topDownPoint(point, in: bounds, isFlipped: isFlipped)
        topDown.y -= TubeMetrics.draftHeadroom
        return topDown
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let artworkY = isFlipped ? bounds.minY + TubeMetrics.draftHeadroom : bounds.minY
        let artwork = CGRect(origin: CGPoint(x: bounds.minX, y: artworkY), size: artworkSize)
        let area = NSTrackingArea(rect: artwork,
                                 options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved],
                                 owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        entered?()
        if containsTubeInteraction(at: convert(event.locationInWindow, from: nil)) { hovered?() }
    }
    override func mouseMoved(with event: NSEvent) {
        if containsTubeInteraction(at: convert(event.locationInWindow, from: nil)) { hovered?() }
    }
    override func mouseExited(with event: NSEvent) { exited?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum TubeHitShape {
    static func contains(_ point: CGPoint, size: CGSize) -> Bool {
        let vesselWidth = size.width - 2 * TubeMetrics.wallInset
        guard point.y >= 0, point.y < size.height,
              point.x >= TubeMetrics.wallInset,
              point.x <= size.width - TubeMetrics.wallInset else { return false }
        if point.y < TubeMetrics.mouthHeight / 2 {
            return PetHitRegions.containsEllipse(point,
                in: CGRect(x: TubeMetrics.wallInset, y: 0,
                           width: vesselWidth, height: TubeMetrics.mouthHeight))
        }
        if point.y > size.height - TubeMetrics.baseHeight / 2 {
            let footOffset = (TubeMetrics.footSpacing + TubeMetrics.footWidth) / 2
            for x in [size.width / 2 - footOffset, size.width / 2 + footOffset] {
                let foot = CGRect(x: x - TubeMetrics.footWidth / 2,
                                  y: size.height - TubeMetrics.footBottom - TubeMetrics.footHeight,
                                  width: TubeMetrics.footWidth, height: TubeMetrics.footHeight)
                if PetHitRegions.containsEllipse(point, in: foot) { return true }
            }
            return PetHitRegions.containsEllipse(point,
                in: CGRect(x: TubeMetrics.wallInset, y: size.height - TubeMetrics.baseHeight,
                           width: vesselWidth, height: TubeMetrics.baseHeight))
        }
        return true
    }
}

@MainActor
final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class TuckedTubeHitView: NSView {
    var presentation: TubeDockPresentation?
    var hovered: (() -> Void)?
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    var reveal: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    private var isOverArtwork = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Show Delay No More")
        toolTip = "Show Delay No More"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { reveal?() }
    override func accessibilityPerformPress() -> Bool { reveal?(); return true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return containsArtwork(at: local) ? self : nil
    }

    func containsArtwork(at point: NSPoint) -> Bool {
        guard let presentation, bounds.contains(point) else { return false }
        let topDown = PetHitRegions.topDownPoint(point, in: bounds, isFlipped: isFlipped)
        return TubeHitShape.contains(presentation.artworkPoint(from: topDown), size: presentation.artworkSize)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { updateHover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { updateHover(at: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { resetHover() }

    func resetHover() {
        guard isOverArtwork else { return }
        isOverArtwork = false
        exited?()
    }

    func updateHover(at point: NSPoint) {
        guard containsArtwork(at: point) else { resetHover(); return }
        hovered?()
        guard !isOverArtwork else { return }
        isOverArtwork = true
        entered?()
    }
}
