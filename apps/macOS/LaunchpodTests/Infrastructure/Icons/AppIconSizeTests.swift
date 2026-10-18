import Foundation
import Testing
@testable import Launchpod

struct AppIconSizeTests {
    @Test(arguments: [CGFloat(1), 2])
    func backingScaleChangesPixelsWithoutChangingLogicalSize(scale: CGFloat) throws {
        let size = try AppIconSize(pointSize: CGSize(width: 48, height: 32), backingScale: scale)

        #expect(size.pointSize == CGSize(width: 48, height: 32))
        #expect(size.backingScale == scale)
        #expect(size.pixelWidth == Int(48 * scale))
        #expect(size.pixelHeight == Int(32 * scale))
    }

    @Test
    func fractionalPointDimensionsCoverTheRequestedExtent() throws {
        let size = try AppIconSize(pointSize: CGSize(width: 23.25, height: 15.75), backingScale: 2)

        #expect(size.pixelWidth == 47)
        #expect(size.pixelHeight == 32)
    }

    @Test
    func equalPixelCountsDoNotCollapseDifferentLogicalSizes() throws {
        let smallRetina = try AppIconSize(pointSize: CGSize(width: 32, height: 32), backingScale: 2)
        let largeStandard = try AppIconSize(pointSize: CGSize(width: 64, height: 64), backingScale: 1)

        #expect(smallRetina.pixelWidth == largeStandard.pixelWidth)
        #expect(smallRetina != largeStandard)
        #expect(Set([smallRetina, largeStandard, smallRetina]).count == 2)
    }

    @Test(arguments: [CGFloat.zero, -1, .nan, .infinity, -.infinity])
    func rejectsInvalidDimensionsAndScale(value: CGFloat) {
        #expect(throws: (any Error).self) {
            try AppIconSize(pointSize: CGSize(width: value, height: 32), backingScale: 1)
        }
        #expect(throws: (any Error).self) {
            try AppIconSize(pointSize: CGSize(width: 32, height: value), backingScale: 1)
        }
        #expect(throws: (any Error).self) {
            try AppIconSize(pointSize: CGSize(width: 32, height: 32), backingScale: value)
        }
    }

    @Test
    func rejectsPixelAndCostOverflowBeforeIntegerConversion() {
        #expect(throws: (any Error).self) {
            try AppIconSize(pointSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 32), backingScale: 2)
        }
        #expect(throws: (any Error).self) {
            try AppIconSize(pointSize: CGSize(width: CGFloat(Int.max), height: 32), backingScale: 1)
        }
    }
}
