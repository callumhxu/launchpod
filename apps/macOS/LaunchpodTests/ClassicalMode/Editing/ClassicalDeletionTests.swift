import AppKit
import XCTest
@testable import Launchpod

@MainActor
final class ClassicalDeletionTests: XCTestCase {
    private let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                        dock: .bottom(extent: 59))

    func testOnlyASuccessfulConfirmedRemovalNotifiesTheLayout() async throws {
        let restore = try NativeAppTestSupport.isolateHostWindows()
        defer { restore() }
        let content = NSView(frame: CGRect(origin: .zero, size: geometry.screenSize))
        content.wantsLayer = true
        let window = NativeAppTestSupport.makeKeyPanel(size: geometry.screenSize, contentView: content)
        defer { window.close() }
        let record = try appRecord()
        let board = ClassicalSpringboard()
        board.deletability.isDeletable = { _ in true }
        content.layer?.addSublayer(board.pager.layer)
        board.show([record], geometry: geometry, scale: 1, rightToLeft: false,
                   noResultsText: "No Results") { _, _ in throw CancellationError() }
        let cell = try XCTUnwrap(board.cell(for: record.id))
        let deletion = ClassicalDeletion()
        deletion.springboard = board
        var excluded: [AppIdentity] = []
        deletion.didRemoveRecord = { excluded.append($0) }
        var attempts = 0
        deletion.remove = { _ in
            attempts += 1
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(userCanceledErr))
        }

        deletion.present(record, cell: cell, in: content)
        XCTAssertTrue(deletion.isPanelShown)
        deletion.dismiss()
        XCTAssertFalse(deletion.isActive)
        XCTAssertEqual(attempts, 0)
        XCTAssertTrue(excluded.isEmpty, "Cancelling the confirmation does not exclude the app")

        deletion.present(record, cell: cell, in: content)
        deletion.panel?.confirm()
        try await waitUntil { !deletion.isActive }
        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(excluded.isEmpty, "An unsuccessful Finder removal does not exclude the app")
        XCTAssertEqual(board.records.map(\.id), [record.id])

        deletion.remove = { _ in attempts += 1 }
        deletion.present(record, cell: cell, in: content)
        deletion.panel?.confirm()
        try await waitUntil { excluded == [record.id] }
        XCTAssertEqual(attempts, 2)
    }

    private func appRecord() throws -> AppRecord {
        let url = URL(filePath: "/Applications/DeletionTest.app", directoryHint: .isDirectory)
        return AppRecord(
            metadata: try AppMetadata(bundleIdentifier: "com.example.DeletionTest", bundleURL: url,
                                      displayName: "Deletion Test", version: nil, buildVersion: nil,
                                      contentModificationDate: nil),
            source: try AppSource(kind: .custom, directoryURL: url.deletingLastPathComponent())
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "Timed out waiting for removal")
    }
}
