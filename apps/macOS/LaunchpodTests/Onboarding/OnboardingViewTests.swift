import AppKit
import CoreML
import SwiftUI
import XCTest
import Vision
@testable import Launchpod

@MainActor
final class OnboardingViewTests: XCTestCase {
    func testFinalStepOffersGetStartedAndOmitsIntermediateNavigationControls() async throws {
        try NativeAppTestSupport.requireNativeWindowTests()
        let text = try await finalStepText()

        XCTAssertTrue(text.contains("Get Started"), text)
        XCTAssertFalse(text.contains("Continue"), text)
        XCTAssertFalse(text.contains("Skip Introduction"), text)
    }

    func testMinimumSizePagesProduceReviewableLocalizedSnapshots() throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let size = OnboardingParameters.minimumWindowSize

        for locale in ["en", "zh-Hans", "zh-Hant", "fr", "de", "ja", "ko", "es"] {
            for step in OnboardingModel.Step.allCases {
                let model = OnboardingModel(defaults: defaults)
                model.begin(at: step)
                let content = OnboardingView(
                    model: model,
                    finish: {},
                    openSettings: {}
                )
                    .environment(\.locale, Locale(identifier: locale))
                    .environment(\.colorScheme, .light)
                    .transaction { $0.disablesAnimations = true }
                    .frame(width: size.width, height: size.height)
                    .background(Color.white)
                let name = "onboarding-\(step)-\(locale)-minimum-size"
                let bitmap = try captureOffscreen(content, size: size)
                XCTAssertTrue(hasPageContent(bitmap), "The page content is blank in \(name)")
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
                try exportIfRequested(png, name: name)
            }
        }
    }

    private func captureOffscreen(_ content: some View, size: CGSize) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        defer { window.close() }
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(window.isKeyWindow)
        return bitmap
    }

    private func settle(_ window: NSWindow) async throws {
        try await Task.sleep(for: .milliseconds(150))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
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
                    throw NSError(domain: "LaunchpodTests.OnboardingOCR", code: 1)
                }
                request.setComputeDevice(cpu, for: stage)
            }
            try VNImageRequestHandler(data: data).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    private func finalStepText() async throws -> String {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { XCTAssertNoThrow(try preferences.cleanup()) }
        let model = OnboardingModel(defaults: defaults)
        model.begin(at: .access)
        let host = NSHostingView(rootView: OnboardingView(
            model: model, finish: {}, openSettings: {}
        ))
        let window = NativeAppTestSupport.makeKeyPanel(
            size: OnboardingParameters.minimumWindowSize, contentView: host
        )
        defer { window.close() }
        try await settle(window)
        return try await recognizedText(in: host)
    }

    private func hasPageContent(_ bitmap: NSBitmapImageRep) -> Bool {
        var visibleSamples = 0
        // Exclude header and footer so those cannot disguise an empty scroll view.
        for y in stride(from: bitmap.pixelsHigh / 5, to: bitmap.pixelsHigh * 4 / 5, by: 3) {
            for x in stride(from: bitmap.pixelsWide / 5, to: bitmap.pixelsWide * 4 / 5, by: 3) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.9,
                   min(color.redComponent, color.greenComponent, color.blueComponent) < 0.9 {
                    visibleSamples += 1
                    if visibleSamples >= 100 { return true }
                }
            }
        }
        return false
    }

    private func exportIfRequested(_ data: Data, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["LAUNCHPOD_ONBOARDING_PREVIEW_DIRECTORY"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name).appendingPathExtension("png"))
    }
}
