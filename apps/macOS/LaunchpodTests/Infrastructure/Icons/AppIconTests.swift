import AppKit
import Testing
@testable import Launchpod

@MainActor
struct AppIconTests {
    @Test
    func appKitWrappersPreserveLogicalAndPixelSizesWithoutSharingMutableImageState() throws {
        let size = try AppIconSize(pointSize: CGSize(width: 48, height: 32), backingScale: 2)
        let icon = try AppIconTestSupport.icon(size: size)
        let first = icon.makeNSImage()
        let second = icon.makeNSImage()
        let representation = try #require(second.representations.first)

        #expect(first !== second)
        #expect(first.size == size.pointSize)
        #expect(second.size == size.pointSize)
        #expect(representation.pixelsWide == 96)
        #expect(representation.pixelsHigh == 64)
        first.size = CGSize(width: 8, height: 8)
        first.isTemplate = true

        #expect(second.size == size.pointSize)
        #expect(!second.isTemplate)
        #expect(icon.cgImage.width == 96)
        #expect(icon.cgImage.height == 64)
        #expect(icon.makeNSImage().size == size.pointSize)
    }
}
