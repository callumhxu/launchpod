import CoreGraphics

/// The logical drawing size and the pixel density requested by the caller.
nonisolated struct AppIconSize: Hashable, Sendable {
    let pointSize: CGSize
    let backingScale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int

    enum ValidationError: Error {
        case invalidDimensions
        case dimensionsTooLarge
    }

    init(pointSize: CGSize, backingScale: CGFloat) throws {
        guard pointSize.width.isFinite, pointSize.height.isFinite, backingScale.isFinite,
              pointSize.width > 0, pointSize.height > 0, backingScale > 0 else {
            throw ValidationError.invalidDimensions
        }
        let width = (pointSize.width * backingScale).rounded(.up)
        let height = (pointSize.height * backingScale).rounded(.up)
        guard width.isFinite, height.isFinite, width >= 1, height >= 1,
              width < CGFloat(Int.max), height < CGFloat(Int.max) else {
            throw ValidationError.dimensionsTooLarge
        }
        let pixelWidth = Int(width)
        let pixelHeight = Int(height)
        guard pixelWidth <= Int.max / 4,
              pixelHeight <= Int.max / (pixelWidth * 4) else {
            throw ValidationError.dimensionsTooLarge
        }
        self.pointSize = pointSize
        self.backingScale = backingScale
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pointSize.width)
        hasher.combine(pointSize.height)
        hasher.combine(backingScale)
    }
}
