import AppKit
import CoreImage
import os

/// Resolves the screen's desktop image without capturing windows or requesting capture access.
@MainActor
final class ClassicalDesktopPicture {
    private let renderer = ClassicalWallpaperRenderer()

    func image(for screen: NSScreen) async throws -> CGImage {
        let workspace = NSWorkspace.shared
        guard let url = workspace.desktopImageURL(for: screen) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        let fill = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB)
        let request = ClassicalWallpaperRenderer.Request(
            url: url,
            size: screen.frame.size,
            scale: screen.backingScaleFactor,
            scaling: (options[.imageScaling] as? NSNumber)?.uintValue
                ?? NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            allowClipping: (options[.allowClipping] as? NSNumber)?.boolValue ?? options.isEmpty,
            fill: fill.map { SIMD3(Double($0.redComponent), Double($0.greenComponent), Double($0.blueComponent)) },
            colorSpace: screen.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return try await renderer.image(for: request)
    }
}

/// Serializes image decoding and scaling away from the window's main-actor lifecycle.
///
/// Work runs on a queue pinned to default QoS: ImageIO and Core Image block on their own
/// default-QoS workers, so running at the caller's user-initiated QoS inverts priorities.
final class ClassicalWallpaperRenderer: @unchecked Sendable {
    struct Request: Sendable {
        let url: URL
        let size: CGSize
        let scale: CGFloat
        let scaling: UInt
        let allowClipping: Bool
        let fill: SIMD3<Double>?
        let colorSpace: CGColorSpace

        func matches(_ other: Self) -> Bool {
            url == other.url && size == other.size && scale == other.scale
                && scaling == other.scaling && allowClipping == other.allowClipping
                && fill == other.fill && CFEqual(colorSpace, other.colorSpace)
        }
    }

    static let workQoS = DispatchQoS.default
    private let queue = DispatchQueue(label: "Launchpod.ClassicalWallpaperRenderer", qos: workQoS)
    // Confined to `queue`.
    private lazy var context = CIContext(options: [.cacheIntermediates: false])
    private var cached: (request: Request, modification: Date?, image: CGImage)?

    func image(for request: Request) async throws -> CGImage {
        try await perform { [self] isCancelled in try render(request, isCancelled: isCancelled) }
    }

    /// Runs `work` on the renderer queue at `workQoS` regardless of the awaiting task's priority.
    func perform<Value: Sendable>(_ work: @escaping @Sendable (_ isCancelled: () -> Bool) throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async(qos: Self.workQoS, flags: .enforceQoS) {
                    continuation.resume(with: Result { try work { cancelled.withLock { $0 } } })
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    private func render(_ request: Request, isCancelled: () -> Bool) throws -> CGImage {
        func checkCancellation() throws {
            if isCancelled() { throw CancellationError() }
        }
        try checkCancellation()
        guard request.size.width > 0, request.size.height > 0, request.scale > 0,
              request.size.width.isFinite, request.size.height.isFinite, request.scale.isFinite else {
            throw CocoaError(.coderInvalidValue)
        }
        let modification = try request.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached, cached.request.matches(request), cached.modification == modification {
            return cached.image
        }
        guard let source = CIImage(contentsOf: request.url, options: [.applyOrientationProperty: true]),
              !source.extent.isEmpty, !source.extent.isInfinite else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: request.url])
        }
        let bounds = CGRect(origin: .zero, size: CGSize(
            width: ceil(request.size.width * request.scale),
            height: ceil(request.size.height * request.scale)
        ))
        let imageRect = Self.imageRect(sourceSize: source.extent.size, request: request)
        let transformed = source.transformed(by: CGAffineTransform(
            translationX: -source.extent.minX, y: -source.extent.minY
        )).transformed(by: CGAffineTransform(
            scaleX: imageRect.width / source.extent.width,
            y: imageRect.height / source.extent.height
        )).transformed(by: CGAffineTransform(translationX: imageRect.minX, y: imageRect.minY))
        let desktop: CIImage
        if let fill = request.fill {
            desktop = transformed.composited(over: CIImage(color: CIColor(
                red: fill.x, green: fill.y, blue: fill.z, alpha: 1
            ))).cropped(to: bounds)
        } else if imageRect.contains(bounds) && isOpaque(source) {
            desktop = transformed.cropped(to: bounds)
        } else {
            // Without the configured fill color, inventing a border would change the desktop.
            throw CocoaError(.coderValueNotFound)
        }
        try checkCancellation()
        guard let image = context.createCGImage(desktop, from: bounds, format: .RGBA8, colorSpace: request.colorSpace) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: request.url])
        }
        try checkCancellation()
        cached = (request, modification, image)
        return image
    }

    private func isOpaque(_ image: CIImage) -> Bool {
        if image.isOpaque { return true }
        let minimum = image.applyingFilter("CIAreaMinimum", parameters: [
            kCIInputExtentKey: CIVector(cgRect: image.extent)
        ])
        var rgba = [Float](repeating: 0, count: 4)
        context.render(minimum, toBitmap: &rgba, rowBytes: 16,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        return rgba[3] == 1
    }

    /// Centers the image using the desktop's scaling and clipping options, in backing pixels.
    static func imageRect(sourceSize: CGSize, request: Request) -> CGRect {
        let target = CGSize(width: ceil(request.size.width * request.scale), height: ceil(request.size.height * request.scale))
        let x = target.width / sourceSize.width
        let y = target.height / sourceSize.height
        let size: CGSize
        switch NSImageScaling(rawValue: request.scaling) {
        case .scaleAxesIndependently:
            size = target
        case .scaleNone:
            size = sourceSize
        case .scaleProportionallyDown:
            let factor = min(1, request.allowClipping ? max(x, y) : min(x, y))
            size = CGSize(width: sourceSize.width * factor, height: sourceSize.height * factor)
        default:
            let factor = request.allowClipping ? max(x, y) : min(x, y)
            size = CGSize(width: sourceSize.width * factor, height: sourceSize.height * factor)
        }
        return CGRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
