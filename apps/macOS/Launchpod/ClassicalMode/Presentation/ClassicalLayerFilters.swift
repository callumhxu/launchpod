import QuartzCore

/// Core Animation's built-in filters and layer options used by the Classical presentation, reached
/// through Core Animation's private `CAFilter` class, filter-type names and layer keys.
///
/// Filters are created by type name and configured by key, so they compute on encoded colour values
/// as Core Animation does and serialize to the render server like the built-in filter names. When
/// `CAFilter` or `CABackdropLayer` is unavailable the factories return nil and layers stay unfiltered.
nonisolated enum ClassicalLayerFilters {
    /// Filter-type names, which are also the default filter names used in key paths.
    static let multiplyColorType = "multiplyColor"
    static let gaussianBlurType = "gaussianBlur"
    static let colorSaturateType = "colorSaturate"
    static let colorMatrixType = "colorMatrix"
    /// Compositing filter that keeps the darker of the layer and what is behind it.
    static let darkenBlendMode = "darkenBlendMode"
    /// Minification filter with Lanczos resampling.
    static let lanczos = CALayerContentsFilter(rawValue: "lanczos")
    /// The Objective-C type encoding of `CAColorMatrix`, a row-major 4 × 5 matrix of floats.
    static let colorMatrixEncoding = "{CAColorMatrix=ffffffffffffffffffff}"

    /// A new filter of `type`, or nil when `CAFilter` is unavailable.
    static func filter(type: String) -> NSObject? {
        guard let filterClass: AnyObject = NSClassFromString("CAFilter") else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else { return nil }
        return filterClass.perform(selector, with: type)?.takeUnretainedValue() as? NSObject
    }

    /// Multiplies each colour channel by a generic gray.
    static func multiplyColor(gray: CGFloat) -> NSObject? {
        let filter = filter(type: multiplyColorType)
        filter?.setValue(CGColor(gray: gray, alpha: 1), forKey: "inputColor")
        return filter
    }

    /// Gaussian blur; with hard edges the blur does not fade toward transparent at the layer's edges.
    static func gaussianBlur(radius: CGFloat, hardEdges: Bool) -> NSObject? {
        let filter = filter(type: gaussianBlurType)
        filter?.setValue(hardEdges, forKey: "inputHardEdges")
        filter?.setValue(radius, forKey: "inputRadius")
        return filter
    }

    static func colorSaturate(amount: CGFloat) -> NSObject? {
        let filter = filter(type: colorSaturateType)
        filter?.setValue(amount, forKey: "inputAmount")
        return filter
    }

    /// `matrix` holds 20 values, row-major: each output channel is `r g b a` weights plus a bias.
    static func colorMatrix(_ matrix: [Float]) -> NSObject? {
        guard matrix.count == 20, let filter = filter(type: colorMatrixType) else { return nil }
        let value = matrix.withUnsafeBytes { bytes in
            NSValue(bytes: bytes.baseAddress!, objCType: colorMatrixEncoding)
        }
        filter.setValue(value, forKey: "inputColorMatrix")
        return filter
    }

    /// A layer that filters what is rendered behind it through its `backgroundFilters`, or nil when
    /// `CABackdropLayer` is unavailable.
    @MainActor static func makeBackdropLayer() -> CALayer? {
        (NSClassFromString("CABackdropLayer") as? CALayer.Type)?.init()
    }

    /// A CoreMaterial `MTMaterialLayer` (a backdrop layer) configured from the material recipe
    /// `recipe` in `bundle`, or nil when the class or its recipe setter is unavailable.
    @MainActor static func makeMaterialLayer(recipe: String, in bundle: Bundle) -> CALayer? {
        guard let layer = (NSClassFromString("MTMaterialLayer") as? CALayer.Type)?.init() else { return nil }
        guard setMaterialRecipe(recipe, in: bundle, on: layer) else { return nil }
        return layer
    }

    /// Switches a layer from `makeMaterialLayer` to another recipe; false when it cannot.
    @MainActor @discardableResult
    static func setMaterialRecipe(_ recipe: String, in bundle: Bundle, on layer: CALayer) -> Bool {
        let selector = NSSelectorFromString("setRecipeName:fromBundle:")
        guard layer.responds(to: selector) else { return false }
        layer.perform(selector, with: recipe, with: bundle)
        return true
    }

    /// Makes `layer`'s sublayers blend with what is behind `layer` instead of inside it
    /// (`allowsGroupBlending` off).
    @MainActor static func disableGroupBlending(_ layer: CALayer) {
        guard layer.responds(to: NSSelectorFromString("setAllowsGroupBlending:")) else { return }
        layer.setValue(false, forKey: "allowsGroupBlending")
    }
}
