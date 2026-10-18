import CoreImage
import QuartzCore

/// Reads the compositing filters set anywhere in a layer tree.
nonisolated enum LayerCompositingFilters {
    /// Every layer in `root`'s tree, `root` included, with its compositing filter, if any.
    static func all(in root: CALayer) -> [(layer: CALayer, filter: Any)] {
        var found: [(layer: CALayer, filter: Any)] = []
        var pending = [root]
        while let layer = pending.popLast() {
            if let filter = layer.compositingFilter { found.append((layer, filter)) }
            pending.append(contentsOf: layer.sublayers ?? [])
        }
        return found
    }

    /// Whether `filter` is a `CIFilter` subclass defined in the application rather than a system
    /// Core Image filter or a filter referenced by name.
    static func isApplicationDefinedCIFilter(_ filter: Any) -> Bool {
        guard let filter = filter as? CIFilter else { return false }
        return Bundle(for: type(of: filter)) == Bundle.main
    }
}
