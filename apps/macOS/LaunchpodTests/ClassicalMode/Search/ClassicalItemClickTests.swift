import AppKit
import XCTest
@testable import Launchpod

/// Press darkens the icon, release over it opens.
@MainActor
final class ClassicalItemClickTests: XCTestCase {
    private let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956), dock: .bottom(extent: 59))

    func testClickOnAnIconLaunchesAndLeavingTheIconCancels() throws {
        let springboard = ClassicalSpringboard()
        springboard.show(try ["Calendar", "Safari"].map(record), geometry: geometry, scale: 1, rightToLeft: false,
                         noResultsText: "No Results") { _, _ in throw CancellationError() }
        let content = ClassicalContentView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.pager = springboard.pager
        content.springboard = springboard
        var launched: [String] = []
        var dismissals = 0
        content.launch = { launched.append($0.metadata.displayName) }
        content.dismiss = { dismissals += 1 }
        let cell = try XCTUnwrap(springboard.pager.pages.first?.itemLayers[1])
        let image = try solidImage()
        cell.setIcon(image)
        let icon = cell.convert(cell.iconLayer.frame, to: springboard.pager.layer)
            .offsetBy(dx: springboard.pager.layer.frame.minX, dy: springboard.pager.layer.frame.minY)
        let center = CGPoint(x: icon.midX, y: icon.midY)

        content.mouseDown(with: try mouse(.leftMouseDown, center, 0))
        XCTAssertTrue(cell.isDarkened)
        XCTAssertEqual(CoreAnimationFilterReading.types(cell.iconLayer.filters), ["multiplyColor"],
                       "The pressed icon is multiplied by gray")
        XCTAssertTrue(cell.iconLayer.contents as AnyObject? === image, "The icon image itself is unchanged")
        content.mouseUp(with: try mouse(.leftMouseUp, center, 0.1))
        XCTAssertFalse(cell.isDarkened)
        XCTAssertNil(cell.iconLayer.filters)
        XCTAssertTrue(cell.iconLayer.contents as AnyObject? === image)
        XCTAssertEqual(launched, ["Safari"])
        XCTAssertEqual(dismissals, 0, "A click on an icon is not a blank click")

        content.mouseDown(with: try mouse(.leftMouseDown, center, 1))
        let outside = CGPoint(x: center.x, y: icon.maxY + 40)
        content.mouseDragged(with: try mouse(.leftMouseDragged, outside, 1.1))
        XCTAssertFalse(cell.isDarkened, "Leaving the icon restores it")
        XCTAssertNil(cell.iconLayer.filters)
        content.mouseUp(with: try mouse(.leftMouseUp, outside, 1.2))
        XCTAssertEqual(launched, ["Safari"])

        content.mouseDown(with: try mouse(.leftMouseDown, center, 2))
        content.mouseDragged(with: try mouse(.leftMouseDragged, CGPoint(x: center.x - 200, y: center.y), 2.05))
        XCTAssertFalse(cell.isDarkened, "A horizontal drag turns the page instead")
        content.mouseUp(with: try mouse(.leftMouseUp, CGPoint(x: center.x - 200, y: center.y), 2.1))
        XCTAssertEqual(launched, ["Safari"])
    }

    func testRestrictedMarkerDoesNotSuppressIconClick() throws {
        let springboard = ClassicalSpringboard()
        springboard.show(try [record("Limited")], geometry: geometry, scale: 2, rightToLeft: false,
                         noResultsText: "No Results") { _, _ in throw CancellationError() }
        let content = ClassicalContentView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.pager = springboard.pager
        content.springboard = springboard
        var opened: [String] = []
        content.launch = { opened.append($0.metadata.displayName) }
        let cell = try XCTUnwrap(springboard.pager.pages.first?.itemLayers.first)
        cell.setIcon(try solidImage())
        cell.setRestricted(true)
        XCTAssertNotNil(cell.restrictedLayer)

        let icon = cell.convert(cell.iconLayer.frame, to: springboard.pager.layer)
            .offsetBy(dx: springboard.pager.layer.frame.minX, dy: springboard.pager.layer.frame.minY)
        let center = CGPoint(x: icon.midX, y: icon.midY)
        content.mouseDown(with: try mouse(.leftMouseDown, center, 0))
        content.mouseUp(with: try mouse(.leftMouseUp, center, 0.1))

        XCTAssertEqual(opened, ["Limited"])
        XCTAssertTrue(cell.isRestricted)
    }

    /// Below the page area the launcher closes on the press itself.
    func testPressBelowThePageAreaDismissesImmediately() throws {
        let springboard = ClassicalSpringboard()
        springboard.show(try ["Safari"].map(record), geometry: geometry, scale: 1, rightToLeft: false,
                         noResultsText: "No Results") { _, _ in throw CancellationError() }
        CALayer().addSublayer(springboard.pager.layer)
        let content = ClassicalContentView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.pager = springboard.pager
        content.springboard = springboard
        var dismissals = 0
        content.dismiss = { dismissals += 1 }
        let band = CGPoint(x: 700, y: geometry.contentFrame.minY - 10)
        content.mouseDown(with: try mouse(.leftMouseDown, band, 0))
        XCTAssertEqual(dismissals, 1, "No release is needed below the page area")
        content.mouseUp(with: try mouse(.leftMouseUp, band, 0.1))
        XCTAssertEqual(dismissals, 1)
        let page = CGPoint(x: 700, y: geometry.contentFrame.minY + 5)
        content.mouseDown(with: try mouse(.leftMouseDown, page, 1))
        XCTAssertEqual(dismissals, 1, "Inside the page area a blank click waits for the release")
        content.mouseUp(with: try mouse(.leftMouseUp, page, 1.1))
        XCTAssertEqual(dismissals, 2)
    }

    private func mouse(_ type: NSEvent.EventType, _ location: CGPoint, _ time: TimeInterval) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: time, windowNumber: 0,
                                         context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    private func record(_ name: String) throws -> AppRecord {
        let url = URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory)
        return AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(UUID().uuidString)", bundleURL: url,
                                      displayName: name, version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
    }

    private func solidImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                             bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try XCTUnwrap(context.makeImage())
    }
}
