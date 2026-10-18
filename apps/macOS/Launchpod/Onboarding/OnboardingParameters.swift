import SwiftUI

/// Geometry for Launchpod's introductory illustrations and reading layout.
enum OnboardingParameters {
    static let windowSize = CGSize(width: 760, height: 580)
    static let minimumWindowSize = CGSize(width: 680, height: 520)
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 16
    static let itemSpacing: CGFloat = 10
    static let compactSpacing: CGFloat = 8
    static let contentWidth: CGFloat = 540
    static let heroIconSize: CGFloat = 64
    static let tileSize: CGFloat = 48
    static let tileSymbolSize: CGFloat = 22
    static let demoRowHeight: CGFloat = 72
    static let tileCornerRadius: CGFloat = 14
    static let panelCornerRadius: CGFloat = 24
    static let sampleItemWidth: CGFloat = 76
    static let folderStageHeight: CGFloat = 176
    static let folderPreviewScale: CGFloat = 0.55
    static let folderPreviewWidth: CGFloat = 40
    static let glassStageHeight: CGFloat = 180
    static let glassExpandedWidth: CGFloat = 280
    static let demoPause: Duration = .milliseconds(1200)
    static let transition: Animation = .smooth
    static let demonstration: Animation = .spring
}
