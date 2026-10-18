import AppKit

/// An immutable raster that can be shared across loading and presentation actors.
nonisolated struct AppIcon: Sendable {
    let cgImage: CGImage
    let size: AppIconSize

    /// Each caller owns its mutable AppKit wrapper; cached rasters remain shared.
    @MainActor func makeNSImage() -> NSImage {
        NSImage(cgImage: cgImage, size: size.pointSize)
    }
}
