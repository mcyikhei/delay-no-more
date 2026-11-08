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
