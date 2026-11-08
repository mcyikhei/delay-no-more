import Foundation
import CoreGraphics
import XCTest
@testable import DelayCore

final class PetHitRegionsTests: XCTestCase {
    func testFlippedAndUnflippedContentProduceSameRootPoint() {
        let bounds = CGRect(x: 10, y: 20, width: 320, height: 500)
        let unflipped = PetHitRegions.topDownPoint(CGPoint(x: 60, y: 450), in: bounds, isFlipped: false)
        let flipped = PetHitRegions.topDownPoint(CGPoint(x: 60, y: 90), in: bounds, isFlipped: true)
        XCTAssertEqual(unflipped, CGPoint(x: 50, y: 70))
        XCTAssertEqual(flipped, unflipped)
    }

    func testLogicalPointConversionHandlesNegativeBoundsWithoutScaling() {
        let bounds = CGRect(x: -200, y: -80, width: 320, height: 500)
        XCTAssertEqual(PetHitRegions.topDownPoint(CGPoint(x: -125, y: 380), in: bounds, isFlipped: false),
                       CGPoint(x: 75, y: 40))
    }

    func testMouthEllipseExcludesItsCenterButNotBoundingBoxCorners() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
        let mouth = CGRect(x: 24, y: 5, width: 272, height: 34)
        XCTAssertTrue(PetHitRegions.containsEllipse(CGPoint(x: 160, y: 22), in: mouth))
        XCTAssertFalse(PetHitRegions.containsEllipse(CGPoint(x: 25, y: 6), in: mouth))
        XCTAssertFalse(PetHitRegions.isBackgroundDrag(at: CGPoint(x: 160, y: 22), in: bounds, mouth: mouth, protectedRects: []))
        XCTAssertTrue(PetHitRegions.isBackgroundDrag(at: CGPoint(x: 25, y: 6), in: bounds, mouth: mouth, protectedRects: []))
    }

    func testDegenerateAndInvalidEllipsesDoNotContainPoints() {
        XCTAssertFalse(PetHitRegions.containsEllipse(.zero, in: .zero))
        XCTAssertFalse(PetHitRegions.containsEllipse(.zero, in: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 40)))
        XCTAssertFalse(PetHitRegions.containsEllipse(CGPoint(x: CGFloat.nan, y: 2), in: CGRect(x: 0, y: 0, width: 30, height: 40)))
    }

    func testCardsEditorAndBaseControlsPreventPetDragging() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
        let mouth = CGRect(x: 24, y: 5, width: 272, height: 34)
        let protected = [CGRect(x: 38, y: 62, width: 244, height: 70),
                         CGRect(x: 38, y: 150, width: 244, height: 250),
                         CGRect(x: 50, y: 450, width: 30, height: 30)]
        for point in [CGPoint(x: 80, y: 90), CGPoint(x: 100, y: 200), CGPoint(x: 65, y: 465)] {
            XCTAssertFalse(PetHitRegions.isBackgroundDrag(at: point, in: bounds, mouth: mouth, protectedRects: protected))
        }
        XCTAssertTrue(PetHitRegions.isBackgroundDrag(at: CGPoint(x: 30, y: 250), in: bounds, mouth: mouth, protectedRects: protected))
    }

    func testScrolledCardProtectionIsClippedToVisibleViewport() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
        let mouth = CGRect(x: 24, y: 5, width: 272, height: 34)
        let viewport = CGRect(x: 38, y: 60, width: 244, height: 350)
        let partial = CGRect(x: 38, y: 380, width: 244, height: 70).intersection(viewport)
        let offscreen = CGRect(x: 38, y: 450, width: 244, height: 70).intersection(viewport)
        XCTAssertFalse(PetHitRegions.isBackgroundDrag(at: CGPoint(x: 100, y: 400), in: bounds, mouth: mouth, protectedRects: [partial, offscreen]))
        XCTAssertTrue(PetHitRegions.isBackgroundDrag(at: CGPoint(x: 100, y: 430), in: bounds, mouth: mouth, protectedRects: [partial, offscreen]))
    }

    func testOutsideBoundsAndInvalidGeometryNeverStartPetDrag() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
        let mouth = CGRect(x: 24, y: 5, width: 272, height: 34)
        for point in [CGPoint(x: -1, y: 100), CGPoint(x: 320, y: 100), CGPoint(x: 20, y: 501), CGPoint(x: CGFloat.nan, y: 100)] {
            XCTAssertFalse(PetHitRegions.isBackgroundDrag(at: point, in: bounds, mouth: mouth, protectedRects: []))
        }
        XCTAssertFalse(PetHitRegions.isBackgroundDrag(at: CGPoint(x: 30, y: 100), in: bounds, mouth: .zero, protectedRects: []))
    }

    func testPanelResizeUsesCurrentHeightRatherThanStaleBottomOrigin() {
        let local = CGPoint(x: 100, y: 280)
        XCTAssertEqual(PetHitRegions.topDownPoint(local, in: CGRect(x: 0, y: 0, width: 320, height: 300), isFlipped: false), CGPoint(x: 100, y: 20))
        XCTAssertEqual(PetHitRegions.topDownPoint(local, in: CGRect(x: 0, y: 0, width: 320, height: 500), isFlipped: false), CGPoint(x: 100, y: 220))
    }
}
