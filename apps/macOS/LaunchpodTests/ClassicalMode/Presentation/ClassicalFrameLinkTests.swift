import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalFrameLinkTests: XCTestCase {
    func testStartIsIdempotentAndStopReleasesTheCallbackOwner() {
        let link = ClassicalFrameLink()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        var first: NSObject? = NSObject()
        weak let retainedFirst = first
        var ignored: NSObject? = NSObject()
        weak let retainedIgnored = ignored
        XCTAssertFalse(link.isRunning)
        autoreleasepool { link.start(in: view) { [owner = first!] in _ = owner } }
        link.start(in: view) { [owner = ignored!] in _ = owner }
        first = nil
        ignored = nil
        XCTAssertTrue(link.isRunning)
        XCTAssertNotNil(retainedFirst)
        XCTAssertNil(retainedIgnored, "Starting twice must not replace or retain another callback")
        link.stop()
        XCTAssertFalse(link.isRunning)
        XCTAssertNil(retainedFirst, "Invalidation releases the display link target and its callback")
        link.stop()
        link.start(in: view) {}
        XCTAssertTrue(link.isRunning, "A stopped link can restart")
        link.stop()
    }

    func testDeinitializationReleasesTheCallback() {
        var link: ClassicalFrameLink? = ClassicalFrameLink()
        var owner: NSObject? = NSObject()
        weak let retained = owner
        autoreleasepool { link?.start(in: NSView()) { [owner = owner!] in _ = owner } }
        owner = nil
        XCTAssertNotNil(retained)
        link = nil
        XCTAssertNil(retained)
    }
}
