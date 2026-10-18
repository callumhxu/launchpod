import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalDesktopStageTests: XCTestCase {
    func testRebuildingDetachesPreviousPresentationAndTeardownClearsTheReplacement() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let size = try AppIconSize(pointSize: CGSize(width: 4, height: 4), backingScale: 1)
        let image = try AppIconTestSupport.icon(size: size).cgImage
        let stage = ClassicalDesktopStage(desktopImage: { _ in image },
                                          menuBarVisibility: ClassicalMenuBarVisibility(resolveOperations: { nil }))
        let host = CALayer()
        let first = stage.build(image: image, screen: screen)
        XCTAssertTrue(first.layers.show(in: host, desktopLayer: first.desktop, reduceMotion: true))
        XCTAssertTrue(first.layers.layer.superlayer === host)
        let replacement = stage.build(image: image, screen: screen)
        XCTAssertNil(first.layers.layer.superlayer)
        XCTAssertNil(first.desktop.superlayer)
        XCTAssertTrue(stage.layers === replacement.layers)
        XCTAssertEqual(replacement.desktop.frame, CGRect(origin: .zero, size: screen.frame.size))
        XCTAssertEqual(replacement.desktop.contentsScale, screen.backingScaleFactor)
        XCTAssertTrue(replacement.desktop.contents as AnyObject? === image)
        XCTAssertTrue(replacement.layers.show(in: host, desktopLayer: replacement.desktop, reduceMotion: true))
        stage.tearDown()
        XCTAssertNil(stage.layers)
        XCTAssertNil(replacement.layers.layer.superlayer)
        XCTAssertNil(replacement.desktop.superlayer)
        stage.tearDown()
    }

    func testCurrentImageFailureIsDeliveredToTheOwner() async throws {
        enum Failure: Error { case unavailable }
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let stage = ClassicalDesktopStage(desktopImage: { _ in throw Failure.unavailable },
                                          menuBarVisibility: ClassicalMenuBarVisibility(resolveOperations: { nil }))
        let delivered = expectation(description: "current image failure delivered")
        stage.loadImage(for: screen, isCurrent: { true }) { result in
            switch result {
            case .success: XCTFail("A failing image provider must not deliver success")
            case let .failure(error): XCTAssertTrue(error is Failure)
            }
            delivered.fulfill()
        }
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertNil(stage.layers, "Loading does not build a presentation")
    }
}
