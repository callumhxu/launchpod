import AppKit
import CoreText
import XCTest
@testable import Launchpod

/// Expected values are worked by hand from the layout formulas.
@MainActor
final class ClassicalSpringboardGeometryTests: XCTestCase {
    func testBottomDockNotchedLaptopScreen() {
        // W 1470, H 956, Dock extent 59, notch 32: content y 89, height 867; unit floor(1470/15) = 98;
        // leftover 867 − 138·5 = 177; side max(49, 90); zoom 0.2 adds 1470·0.2·0.2 = 58.8 → 148;
        // top max(26, 35); bottom max(44, 35). Page height 867 − 30 (search band) − 35 − 32 (notch) − 44 = 726.
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956),
                                                    dock: .bottom(extent: 59), notchHeight: 32)
        XCTAssertEqual(geometry.contentFrame, CGRect(x: 0, y: 89, width: 1470, height: 867))
        XCTAssertEqual(geometry.zoomFactor, 0.2)
        XCTAssertEqual(geometry.margins, .init(left: 148, right: 148, top: 35, bottom: 44))
        XCTAssertEqual(geometry.pageFrame, CGRect(x: 148, y: 133, width: 1174, height: 726))
        XCTAssertEqual(geometry.grid.cellSize, CGSize(width: 167, height: 145))
        XCTAssertEqual(geometry.grid.capacity, 35)
        // 250 × 25, centered; bottom edge 956 − (35 + 32 + 15) = 874.
        XCTAssertEqual(geometry.searchFieldFrame, CGRect(x: 610, y: 874, width: 250, height: 25))
        XCTAssertLessThan(geometry.pageFrame.maxY, geometry.searchFieldFrame.minY, "The first row starts below the search field")


    }

    func testDisplaysWithoutANotchKeepOnlyTheSearchBand() {
        // Same screen without a notch: 867 − 30 − 35 − 44 = 758; search bottom 956 − (35 + 15) = 906.
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956), dock: .bottom(extent: 59))
        XCTAssertEqual(geometry.pageFrame, CGRect(x: 148, y: 133, width: 1174, height: 758))
        XCTAssertEqual(geometry.searchFieldFrame, CGRect(x: 610, y: 906, width: 250, height: 25))
        XCTAssertEqual(geometry.grid.cellSize, CGSize(width: 167, height: 151))
    }

    func testHiddenDockCapsIconsAt128() {
        // W 1920, H 1080: content height 1050; unit 128; leftover 1050 − 168·5 = 210;
        // side 90 + 1920·0.2·0.3 (115.2) → 205; top max(31, 35) = 35; bottom max(52, 35) = 52.
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1920, height: 1080), dock: .hidden)
        XCTAssertEqual(geometry.contentFrame, CGRect(x: 0, y: 30, width: 1920, height: 1050))
        XCTAssertEqual(geometry.zoomFactor, 0.3, "1920 is not wider than 1920")
        XCTAssertEqual(geometry.margins, .init(left: 205, right: 205, top: 35, bottom: 52))
        XCTAssertEqual(geometry.pageFrame, CGRect(x: 205, y: 82, width: 1510, height: 933))
        XCTAssertEqual(geometry.grid.cellSize, CGSize(width: 215, height: 186))
        let item = ClassicalItemLayout(cellSize: geometry.grid.cellSize, titleLineHeight: 16)
        XCTAssertEqual(item.iconFrame, CGRect(x: 43, y: 43, width: 128, height: 128), "186 − 47 exceeds 128; y 20 + 23")
    }

    func testSideDockWidensOnlyItsOwnMarginAndNarrowsTheUnit() {
        // W 2560, H 1440, Dock left 79.2 → 80: unit floor(2480/15) = 165; leftover 1410 − 205·5 = 385;
        // side max(82, 90); zoom 0.6 − 0.1 (side Dock) adds 2560·0.2·0.5 = 256;
        // top floor(57.75) = 57; bottom floor(96.25) = 96.
        let left = ClassicalSpringboardGeometry(screenSize: CGSize(width: 2560, height: 1440), dock: .left(extent: 79.2))
        XCTAssertEqual(left.zoomFactor, 0.5, accuracy: 0.0001)
        XCTAssertEqual(left.margins, .init(left: 426, right: 346, top: 57, bottom: 96))
        XCTAssertEqual(left.pageFrame, CGRect(x: 426, y: 126, width: 1788, height: 1227))
        XCTAssertEqual(left.grid.cellSize, CGSize(width: 255, height: 245))
        let right = ClassicalSpringboardGeometry(screenSize: CGSize(width: 2560, height: 1440), dock: .right(extent: 80))
        XCTAssertEqual(right.margins, .init(left: 346, right: 426, top: 57, bottom: 96))
    }

    func testLargeUnitsWidenTheSideMarginBeyondTheMinimum() {
        // W 5120: unit floor(5120/15) = 341, side floor(341/2) = 170 > 90; zoom 0.6 adds 614.4 → 784.
        let geometry = ClassicalSpringboardGeometry(screenSize: CGSize(width: 5120, height: 2880), dock: .hidden)
        XCTAssertEqual(geometry.margins.left, 784)
        XCTAssertEqual(geometry.margins.right, 784)
    }

    func testZoomFactorTiersFollowScreenWidthAndDropForASideDock() {
        let tiers: [(CGFloat, CGFloat)] = [(1280, 0), (1440, 0), (1441, 0.2), (1680, 0.2), (1681, 0.3), (1920, 0.3), (1921, 0.6), (6016, 0.6)]
        for (width, factor) in tiers {
            XCTAssertEqual(ClassicalSpringboardGeometry.zoomFactor(screenWidth: width, dockOnSide: false), factor, accuracy: 0.0001, "\(width)")
        }
        XCTAssertEqual(ClassicalSpringboardGeometry.zoomFactor(screenWidth: 1470, dockOnSide: true), 0.1, accuracy: 0.0001)
        XCTAssertEqual(ClassicalSpringboardGeometry.zoomFactor(screenWidth: 1280, dockOnSide: true), 0, "Factors of 0.1 or less are not reduced")
    }

    func testRowsAndColumnsAreFixedPreferencesClampedToTwoThroughHundred() {
        XCTAssertEqual(ClassicalSpringboardGeometry.defaultColumns, 7)
        XCTAssertEqual(ClassicalSpringboardGeometry.defaultRows, 5)
        let small = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1024, height: 640), dock: .hidden)
        let large = ClassicalSpringboardGeometry(screenSize: CGSize(width: 6016, height: 3384), dock: .hidden)
        XCTAssertEqual(small.grid.capacity, 35, "Screen size never changes the 7 × 5 capacity")
        XCTAssertEqual(large.grid.capacity, 35)
        let clamped = ClassicalSpringboardGeometry(screenSize: CGSize(width: 1470, height: 956), dock: .hidden,
                                                   rows: 1, columns: 500)
        XCTAssertEqual(clamped.rows, 2)
        XCTAssertEqual(clamped.columns, 100)
    }

}

@MainActor
final class ClassicalGridPreferenceTests: XCTestCase {
    private func defaults() throws -> (UserDefaults, () -> Void) {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        return (defaults, {
            do { try preferences.cleanup() }
            catch { XCTFail("Failed to clean up temporary preferences: \(error)") }
        })
    }

    func testWithoutAnyValuesTheGridIsLaunchpadsSevenByFive() throws {
        let (defaults, remove) = try defaults()
        defer { remove() }
        XCTAssertTrue(ClassicalGridPreference.dimensions(in: defaults, dockValue: { _ in nil }) == (5, 7))
        XCTAssertNil(defaults.object(forKey: ClassicalGridPreference.rowsKey), "Nothing is written without Dock values")
    }

    func testDockValuesAreImportedOnceClampedAndNeverReadAgain() throws {
        let (defaults, remove) = try defaults()
        defer { remove() }
        XCTAssertTrue(ClassicalGridPreference.dimensions(in: defaults, dockValue: { $0 == "springboard-rows" ? 1 : 9 }) == (2, 9),
                      "Imported like the Dock reads them: clamped to 2…100")
        defaults.set(6, forKey: ClassicalGridPreference.rowsKey)
        XCTAssertTrue(ClassicalGridPreference.dimensions(in: defaults, dockValue: { _ in 40 }) == (6, 9),
                      "Launchpod's own values win and the Dock is not consulted again")
    }

    func testValuesAlreadyChosenInLaunchpodAreNotOverwrittenByTheImport() throws {
        let (defaults, remove) = try defaults()
        defer { remove() }
        defaults.set(8, forKey: ClassicalGridPreference.columnsKey)
        XCTAssertTrue(ClassicalGridPreference.dimensions(in: defaults, dockValue: { _ in 4 }) == (4, 8))
        defaults.set(500, forKey: ClassicalGridPreference.columnsKey)
        XCTAssertEqual(ClassicalGridPreference.dimensions(in: defaults, dockValue: { _ in nil }).columns, 100)
    }

    /// The sandbox's read-only exception for `com.apple.dock` lets the import read the Dock's domain.
    func testTheSandboxedAppCanReadTheDockDomain() {
        CFPreferencesAppSynchronize(ClassicalGridPreference.dockDomain)
        XCTAssertNotNil(CFPreferencesCopyAppValue("persistent-apps" as CFString, ClassicalGridPreference.dockDomain))
    }
}
