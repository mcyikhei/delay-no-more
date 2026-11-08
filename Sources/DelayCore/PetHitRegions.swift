import Foundation
import CoreGraphics

/// Pure hit-region decisions shared by the native panel and nonvisual checks.
/// All hit regions use logical points in the SwiftUI root's top-down space.
public enum PetHitRegions {
    /// Convert an AppKit content-local point to a zero-origin, top-down root.
    /// Do not apply a backing-scale factor: both APIs use logical points.
    public static func topDownPoint(_ local: CGPoint, in bounds: CGRect, isFlipped: Bool) -> CGPoint {
        CGPoint(x: local.x - bounds.origin.x,
                y: isFlipped ? local.y - bounds.origin.y : bounds.origin.y + bounds.size.height - local.y)
    }

    public static func containsEllipse(_ point: CGPoint, in rect: CGRect) -> Bool {
        guard finite(point), finite(rect), rect.size.width > 0, rect.size.height > 0 else { return false }
        let x = (point.x - rect.origin.x - rect.size.width / 2) / (rect.size.width / 2)
        let y = (point.y - rect.origin.y - rect.size.height / 2) / (rect.size.height / 2)
        return x * x + y * y <= 1
    }

    /// The caller separately checks window state and the visible pet silhouette.
    /// Protected cards must already be clipped to their visible scroll viewport.
    /// Invalid geometry fails closed, leaving the event with the UI.
    public static func isBackgroundDrag(at point: CGPoint, in bounds: CGRect,
                                        mouth: CGRect, protectedRects: [CGRect]) -> Bool {
        guard finite(point), finite(bounds), bounds.size.width > 0, bounds.size.height > 0,
              contains(point, in: bounds), finite(mouth), mouth.size.width > 0, mouth.size.height > 0 else { return false }
        guard !containsEllipse(point, in: mouth) else { return false }
        for rect in protectedRects {
            // CGRect.null is a normal result of clipping offscreen content.
            if rect.origin.x == .infinity && rect.origin.y == .infinity && rect.size.width == 0 && rect.size.height == 0 { continue }
            guard finite(rect) else { return false }
            if rect.size.width == 0 || rect.size.height == 0 { continue }
            guard rect.size.width > 0, rect.size.height > 0 else { return false }
            if contains(point, in: rect) { return false }
        }
        return true
    }

    private static func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }
    private static func finite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite && rect.size.width.isFinite && rect.size.height.isFinite
    }
    private static func contains(_ point: CGPoint, in rect: CGRect) -> Bool {
        point.x >= rect.origin.x && point.x < rect.origin.x + rect.size.width &&
        point.y >= rect.origin.y && point.y < rect.origin.y + rect.size.height
    }
}
