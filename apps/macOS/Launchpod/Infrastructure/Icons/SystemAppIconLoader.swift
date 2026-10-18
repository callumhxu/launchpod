import AppKit

nonisolated protocol AppIconLoading: Sendable {
    func loadIcon(for metadata: AppMetadata, size: AppIconSize) async throws -> AppIcon
}

/// Serializes system image access and rasterization outside the main actor.
actor SystemAppIconLoader: AppIconLoading {
    enum LoadError: Error {
        case cannotRender
    }

    func loadIcon(for metadata: AppMetadata, size: AppIconSize) async throws -> AppIcon {
        try Task.checkCancellation()
        let icon = try autoreleasepool {
            try renderIcon(at: metadata.bundleURL, size: size)
        }
        try Task.checkCancellation()
        return icon
    }

    private func renderIcon(at url: URL, size: AppIconSize) throws -> AppIcon {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        // NSWorkspace permits this call on any thread and supplies a generic icon on failure.
        // Copy its mutable image before rendering; no NSImage leaves this operation.
        guard let image = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage else {
            throw LoadError.cannotRender
        }
        try Task.checkCancellation()
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: size.pixelWidth, height: size.pixelHeight,
                bitsPerComponent: 8, bytesPerRow: size.pixelWidth * 4,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw LoadError.cannotRender }

        context.clear(CGRect(x: 0, y: 0, width: size.pixelWidth, height: size.pixelHeight))
        context.scaleBy(x: size.backingScale, y: size.backingScale)
        var proposedRect = CGRect(origin: .zero, size: size.pointSize)
        let reference = NSGraphicsContext(cgContext: context, flipped: false)
        guard let source = image.cgImage(forProposedRect: &proposedRect,
                                        context: reference, hints: nil) else {
            throw LoadError.cannotRender
        }

        // Representation selection is advisory; this bitmap defines the exact output dimensions.
        context.interpolationQuality = .high
        context.draw(source, in: proposedRect)
        guard let raster = context.makeImage() else { throw LoadError.cannotRender }
        return AppIcon(cgImage: raster, size: size)
    }
}
