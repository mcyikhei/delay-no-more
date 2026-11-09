import CoreGraphics

/// Track the pointer in screen coordinates so moving the window never shifts
/// the reference point for the next drag event.
public struct PetWindowDrag {
    private let pointerStart: CGPoint
    private let originStart: CGPoint
    public private(set) var hasMoved = false

    public init(pointer: CGPoint, windowOrigin: CGPoint) {
        pointerStart = pointer
        originStart = windowOrigin
    }

    public mutating func move(to pointer: CGPoint) -> CGPoint? {
        let dx = pointer.x - pointerStart.x
        let dy = pointer.y - pointerStart.y
        let origin = CGPoint(x: originStart.x + dx, y: originStart.y + dy)
        guard origin.x.isFinite, origin.y.isFinite else { return nil }
        guard hasMoved || dx * dx + dy * dy >= 9 else { return nil }
        hasMoved = true
        return origin
    }
}

/// A press on the tube body is a click when it never moved far enough to
/// drag the pet and was released quickly; a long still press does nothing.
public enum PetClick {
    public static let maxHold: Double = 0.6

    public static func isClick(moved: Bool, held: Double) -> Bool {
        !moved && held.isFinite && held >= 0 && held < maxHold
    }
}
