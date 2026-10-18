import CoreGraphics
import Foundation

/// Screen-level Classical layout: the content frame, the four page margins, the page rectangle and
/// the search field above it.
///
/// Rows and columns are fixed preferences (7 × 5 by default); only sizes and margins follow the
/// screen. All rectangles use Core Animation coordinates in the screen-sized root layer
/// (origin bottom-left, y up).
struct ClassicalSpringboardGeometry: Equatable, Sendable {
    enum DockPlacement: Equatable, Sendable {
        /// The Dock is not reserved over the launcher (auto-hidden or covered).
        case hidden
        case bottom(extent: CGFloat)
        case left(extent: CGFloat)
        case right(extent: CGFloat)
    }

    struct Margins: Equatable, Sendable {
        var left: CGFloat
        var right: CGFloat
        var top: CGFloat
        var bottom: CGFloat
    }

    static let defaultColumns = 7
    static let defaultRows = 5
    static let gridDimensionRange = 2...100
    /// The band between the top margin and the first row that holds the search field.
    static let searchBandHeight: CGFloat = 30
    static let searchFieldSize = CGSize(width: 250, height: 25)

    let screenSize: CGSize
    let rows: Int
    let columns: Int
    /// The region the pager occupies, above the Dock reserve and the fixed 30 pt bottom band.
    let contentFrame: CGRect
    let margins: Margins
    /// The camera housing's height on displays with a notch; zero elsewhere.
    let notchHeight: CGFloat
    /// Widens the side margins on wide screens.
    let zoomFactor: CGFloat

    init(screenSize: CGSize, dock: DockPlacement, notchHeight: CGFloat = 0,
         rows: Int = defaultRows, columns: Int = defaultColumns) {
        self.screenSize = screenSize
        self.notchHeight = max(notchHeight, 0)
        self.rows = Self.clampedDimension(rows)
        self.columns = Self.clampedDimension(columns)
        let width = screenSize.width
        let height = screenSize.height

        let contentY: CGFloat
        let unitWidth: CGFloat
        var dockLeft: CGFloat = 0
        var dockRight: CGFloat = 0
        switch dock {
        case .hidden:
            contentY = 30
            unitWidth = width
        case .bottom(let extent):
            contentY = Self.roundedExtent(extent) + 30
            unitWidth = width
        case .left(let extent):
            contentY = 30
            unitWidth = width - Self.roundedExtent(extent)
            dockLeft = Self.roundedExtent(extent)
        case .right(let extent):
            contentY = 30
            unitWidth = width - Self.roundedExtent(extent)
            dockRight = Self.roundedExtent(extent)
        }
        let contentHeight = height - contentY
        contentFrame = CGRect(x: 0, y: contentY, width: width, height: contentHeight)

        let unit = (unitWidth / CGFloat(2 * self.columns + 1)).rounded(.down)
        let leftover = (contentHeight - (unit + 40) * CGFloat(self.rows)).rounded(.down)
        let side = max((unit / 2).rounded(.down), 90)
        let dockOnSide: Bool
        switch dock {
        case .left, .right: dockOnSide = true
        case .hidden, .bottom: dockOnSide = false
        }
        zoomFactor = Self.zoomFactor(screenWidth: width, dockOnSide: dockOnSide)
        // Zoom style 0 (the `springboard-zoom-style` default) widens only the side margins.
        let zoomInset = width * 0.2 * zoomFactor
        margins = Margins(
            left: (side + dockLeft + zoomInset).rounded(.down),
            right: (side + dockRight + zoomInset).rounded(.down),
            top: max((leftover * 0.15).rounded(.down), 35),
            bottom: max((leftover * 0.25).rounded(.down), 35)
        )
    }

    /// 0 up to 1440 pt wide, 0.2 up to 1680, 0.3 up to 1920, 0.6 beyond; 0.1 less with a side Dock.
    static func zoomFactor(screenWidth: CGFloat, dockOnSide: Bool) -> CGFloat {
        let factor: CGFloat = screenWidth > 1920 ? 0.6 : screenWidth > 1680 ? 0.3 : screenWidth > 1440 ? 0.2 : 0
        return factor > 0.1 && dockOnSide ? factor - 0.1 : factor
    }

    /// The first page's rectangle in root-layer coordinates; later pages repeat one screen width apart.
    /// Below the top margin and any notch, a fixed band is kept for the search field.
    var pageFrame: CGRect {
        CGRect(x: margins.left, y: contentFrame.minY + margins.bottom,
               width: screenSize.width - margins.left - margins.right,
               height: contentFrame.height - Self.searchBandHeight - margins.top - notchHeight - margins.bottom)
    }

    /// Centered horizontally; its bottom edge sits 15 pt below the top margin and notch.
    var searchFieldFrame: CGRect {
        CGRect(x: screenSize.width / 2 - Self.searchFieldSize.width / 2,
               y: contentFrame.maxY - (margins.top + notchHeight + 15),
               width: Self.searchFieldSize.width, height: Self.searchFieldSize.height)
    }

    var grid: ClassicalGridLayout {
        ClassicalGridLayout(pageSize: pageFrame.size, rows: rows, columns: columns)
    }

    static func clampedDimension(_ value: Int) -> Int {
        value < gridDimensionRange.lowerBound ? gridDimensionRange.lowerBound : min(value, gridDimensionRange.upperBound)
    }

    private static func roundedExtent(_ extent: CGFloat) -> CGFloat {
        max(extent, 0).rounded(.up)
    }
}

/// Rows and columns of the Classical grid, stored in Launchpod's own settings.
///
/// The `com.apple.dock` keys `springboard-rows` (default 5) and `springboard-columns` (default 7),
/// clamped to 2…100, exist only when a user set them with `defaults write`, so Launchpod
/// keeps its own values with the same defaults and range, importing the Dock's once if present.
enum ClassicalGridPreference {
    static let rowsKey = "classicalGridRows"
    static let columnsKey = "classicalGridColumns"
    static let importedKey = "classicalGridImportedDockSettings"
    static let range = ClassicalSpringboardGeometry.gridDimensionRange
    nonisolated static let dockDomain = "com.apple.dock" as CFString

    /// The grid for the next presentation.
    static func dimensions(in defaults: UserDefaults = .standard,
                           dockValue: (String) -> Int? = Self.dockInteger) -> (rows: Int, columns: Int) {
        importDockSettingsIfNeeded(into: defaults, dockValue: dockValue)
        func value(_ key: String, _ fallback: Int) -> Int {
            ClassicalSpringboardGeometry.clampedDimension((defaults.object(forKey: key) as? NSNumber)?.intValue ?? fallback)
        }
        return (value(rowsKey, ClassicalSpringboardGeometry.defaultRows), value(columnsKey, ClassicalSpringboardGeometry.defaultColumns))
    }

    /// Copies a user's `defaults write com.apple.dock springboard-rows/-columns` values once, without
    /// overriding values already chosen in Launchpod. Afterwards the Dock is not read again.
    static func importDockSettingsIfNeeded(into defaults: UserDefaults = .standard,
                                           dockValue: (String) -> Int? = Self.dockInteger) {
        guard !defaults.bool(forKey: importedKey) else { return }
        defaults.set(true, forKey: importedKey)
        for (key, dockKey) in [(rowsKey, "springboard-rows"), (columnsKey, "springboard-columns")]
        where defaults.object(forKey: key) == nil {
            if let value = dockValue(dockKey) {
                defaults.set(ClassicalSpringboardGeometry.clampedDimension(value), forKey: key)
            }
        }
    }

    /// Needs the read-only shared-preference exception for `com.apple.dock` in the sandbox.
    /// CFPreferences reads are thread-safe, so any context may call it.
    nonisolated static func dockInteger(_ key: String) -> Int? {
        CFPreferencesAppSynchronize(dockDomain)
        return (CFPreferencesCopyAppValue(key as CFString, dockDomain) as? NSNumber)?.intValue
    }
}
