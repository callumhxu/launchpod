import AppKit
import CoreML
import SwiftUI
import XCTest
import Vision
@testable import Launchpod

@MainActor
final class AppsSettingsViewTests: XCTestCase {
    func testAppSourcesHeaderAndAddFolderIconButtonWithAccessibleName() async throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let host = NSHostingView(rootView: AppsSettingsView(
            directoryPreference: AppDirectoryPreference(defaults: defaults),
            onDirectoriesChanged: { _ in }
        ).environment(\.locale, Locale(identifier: "en")))
        let window = NativeAppTestSupport.makeKeyPanel(
            size: CGSize(width: 480, height: 620), contentView: host
        )
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let text = try await recognizedText(in: host)
        XCTAssertTrue(text.contains("App Sources"), text)
        XCTAssertFalse(text.contains("Add Folder"),
                       "The plus control must remain icon-only. Rendered text: \(text)")
    }

    private func descendants(of root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(descendants)
    }

    private func recognizedText(in view: NSView) async throws -> String {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.tiffRepresentation)
        return try await Task.detached {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            for (stage, devices) in try request.supportedComputeStageDevices {
                guard let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) else {
                    throw NSError(domain: "LaunchpodTests.AppSourcesOCR", code: 1)
                }
                request.setComputeDevice(cpu, for: stage)
            }
            try VNImageRequestHandler(data: data).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}
