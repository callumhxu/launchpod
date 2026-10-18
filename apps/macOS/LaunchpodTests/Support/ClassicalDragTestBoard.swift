import QuartzCore
import XCTest
@testable import Launchpod

/// A Classical springboard on a plain drag host layer, with named placeholder applications, for
/// tests that drive item drags. It only builds the fixture and converts slot positions; the tests
/// own every expectation.
@MainActor
struct ClassicalDragTestBoard {
    /// A 2 × 3 grid, so a page holds six items.
    static let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                       dock: .bottom(extent: 59), rows: 2, columns: 3)
    let host: CALayer
    let board = ClassicalSpringboard()

    /// Core Animation adds implicit animations only to layers in a window's layer tree; pass a
    /// window's layer-backed view's layer as `host` when a test observes them.
    init(_ pages: [[String]], host: CALayer = CALayer()) throws {
        self.host = host
        board.deletability.isDeletable = { _ in false }
        host.frame = CGRect(origin: .zero, size: Self.geometry.screenSize)
        host.addSublayer(board.pager.layer)
        board.show(pages: try pages.map { try $0.map { .app(try Self.record($0)) } }, geometry: Self.geometry, scale: 1,
                   rightToLeft: false, noResultsText: "No Results") { _, _ in throw CancellationError() }
    }

    /// The centre of `slot` on `page`, in drag-layer coordinates.
    func center(page: Int, slot: Int) -> CGPoint {
        let frame = Self.geometry.grid.cellFrame(at: slot)
        return host.convert(CGPoint(x: frame.midX, y: frame.midY), from: board.pager.pages[page].layer)
    }

    var names: [[String]] { Self.names(board.pages) }

    static func names(_ pages: [[ClassicalPageItem]]) -> [[String]] {
        pages.map { $0.map(\.title) }
    }

    func names(_ layout: ClassicalLayout) -> [[String]] {
        let byID = Dictionary(uniqueKeysWithValues: board.records.map { ($0.id, $0.metadata.displayName) })
        return layout.pages.map { $0.compactMap { $0.app.flatMap { byID[$0] } } }
    }

    static func record(_ name: String) throws -> AppRecord {
        let url = URL(filePath: "/Applications/\(name).app", directoryHint: .isDirectory)
        return AppRecord(
            id: AppIdentity(),
            metadata: try AppMetadata(bundleIdentifier: "com.example.\(UUID().uuidString)", bundleURL: url,
                                      displayName: name, version: nil, buildVersion: nil, contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
    }

    /// Runs the main run loop until `condition` holds or three seconds pass.
    static func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertTrue(condition(), "Timed out.", file: file, line: line)
    }
}
