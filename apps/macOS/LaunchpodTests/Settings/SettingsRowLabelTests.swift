import AppKit
import SwiftUI
import XCTest
@testable import Launchpod

@MainActor
final class SettingsRowLabelTests: XCTestCase {
    func testSubtitleLabelAlignsItsWholeTextBlockAtTheRowCenterWhenItWraps() async throws {
        var heights: [CGFloat] = []
        for width: CGFloat in [340, 150] {
            let measurements = Measurements()
            let fixture = try HostedViewTestSupport(view: MeasurementLayout(measurements: measurements) {
                SettingsRowLabel(
                    title: "Application Icon", subtitle: "Choose the icon shown in the Dock.", systemImage: "app"
                )
            }, size: NSSize(width: width, height: 160))
            defer { fixture.close() }
            try await NativeAppTestSupport.waitUntil(description: "settings label layout") {
                fixture.host.layoutSubtreeIfNeeded()
                return measurements.height > 0
            }
            XCTAssertEqual(measurements.baseline, measurements.height / 2, accuracy: 0.5,
                           "The grouped row aligns at the center of title plus subtitle, including wrapped lines")
            heights.append(measurements.height)
        }
        XCTAssertGreaterThan(heights[1], heights[0], "The narrower label wraps instead of clipping its subtitle")
    }

    func testTrailingControlCanUseTheSameCenterAlignmentGuide() async throws {
        let measurements = Measurements()
        let fixture = try HostedViewTestSupport(view: MeasurementLayout(measurements: measurements) {
            Toggle("", isOn: .constant(true)).labelsHidden().settingsRowCentered()
        }, size: NSSize(width: 160, height: 100))
        defer { fixture.close() }
        try await NativeAppTestSupport.waitUntil(description: "trailing control layout") {
            fixture.host.layoutSubtreeIfNeeded()
            return measurements.height > 0
        }
        XCTAssertEqual(measurements.baseline, measurements.height / 2, accuracy: 0.5)
    }

    private final class Measurements {
        var height: CGFloat = 0
        var baseline: CGFloat = 0
    }

    private struct MeasurementLayout: Layout {
        let measurements: Measurements

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            subviews[0].sizeThatFits(proposal)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let proposal = ProposedViewSize(width: bounds.width, height: nil)
            let dimensions = subviews[0].dimensions(in: proposal)
            measurements.height = dimensions.height
            measurements.baseline = dimensions[.firstTextBaseline]
            subviews[0].place(at: bounds.origin, proposal: proposal)
        }
    }
}
