import CoreGraphics
import DelayCore

enum TubeCardDrop {
    /// Insertion slots stay fixed while the rows animate around the open slot.
    static func destination(at point: CGPoint, height: CGFloat, rowsTop: CGFloat, count: Int) -> Int? {
        guard count > 0, rowsTop.isFinite else { return nil }
        let innerWidth = TubeMetrics.width - 2 * TubeMetrics.wallInset
        let mouth = CGRect(x: TubeMetrics.wallInset, y: 0, width: innerWidth, height: TubeMetrics.mouthHeight)
        if PetHitRegions.containsEllipse(point, in: mouth) { return 0 }

        let viewport = CGRect(x: TubeMetrics.wallInset, y: TubeMetrics.mouthHeight, width: innerWidth,
                              height: max(0, height - TubeMetrics.mouthHeight - TubeMetrics.baseHeight))
        guard viewport.contains(point) else { return nil }

        let stride = TubeMetrics.cardHeight + TubeMetrics.cardSpacing
        let cardWidth = TubeMetrics.width - 2 * TubeMetrics.cardInset
        var nearestIndex: Int?
        var nearestDistance = CGFloat.infinity
        for index in 0..<count {
            let frame = CGRect(x: TubeMetrics.cardInset, y: rowsTop + CGFloat(index) * stride,
                               width: cardWidth, height: TubeMetrics.cardHeight)
            let visible = frame.intersection(viewport)
            guard !visible.isNull, !visible.isEmpty else { continue }
            if (visible.minY..<visible.maxY).contains(point.y) { return index }
            let distance = abs(visible.midY - point.y)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        return nearestIndex
    }
}
