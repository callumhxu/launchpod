import AppKit
import CoreText

/// Icon and title placement inside one Classical cell.
/// Coordinates are cell-local Core Animation coordinates (origin bottom-left, y up).
struct ClassicalItemLayout: Equatable, Sendable {
    static let maximumIconSide: CGFloat = 128
    static let minimumIconSide: CGFloat = 20

    /// The title label's inset around its text layer on every side.
    static let titleInset: CGFloat = 2

    let cellSize: CGSize
    /// The title label's preferred height: one text line, the 2 pt insets above and below, and the
    /// shadow allowance `blur − offset.y` (2 − (−1)).
    let titleHeight: CGFloat
    let iconFrame: CGRect

    init(cellSize: CGSize, titleLineHeight: CGFloat = ClassicalTitleFont.lineHeight) {
        self.cellSize = cellSize
        titleHeight = titleLineHeight + 2 * Self.titleInset + ClassicalTitleFont.shadowBlur - ClassicalTitleFont.shadowOffset.height
        let bottomPadding = Self.bottomPadding(cellHeight: cellSize.height)
        let side = Self.iconSide(cellSize: cellSize, titleHeight: titleHeight)
        iconFrame = CGRect(x: (cellSize.width / 2 - side / 2).rounded(.towardZero),
                           y: bottomPadding + titleHeight, width: side, height: side)
    }

    /// The centered title label frame for a title whose natural single-line width is `textWidth`.
    func titleFrame(textWidth: CGFloat) -> CGRect {
        let width = min(textWidth + 2 * Self.titleInset, cellSize.width - 12)
        let x = cellSize.width / 2 - width / 2
        // Odd widths round to the nearest point; even widths truncate.
        let roundedX = Int(width) % 2 == 0 ? x.rounded(.towardZero) : x.rounded(.toNearestOrAwayFromZero)
        return CGRect(x: roundedX, y: Self.bottomPadding(cellHeight: cellSize.height), width: width, height: titleHeight)
    }

    /// The text layer inside the title label, inset by `titleInset` on every side.
    func titleTextFrame(textWidth: CGFloat) -> CGRect {
        titleFrame(textWidth: textWidth).insetBy(dx: Self.titleInset, dy: Self.titleInset)
    }

    static func bottomPadding(cellHeight: CGFloat) -> CGFloat {
        min((cellHeight / 8).rounded(.up), 20)
    }

    /// The largest 8 pt step that leaves room for the title, capped at 128 and floored at 20.
    static func iconSide(cellSize: CGSize, titleHeight: CGFloat) -> CGFloat {
        let available = min(cellSize.width, cellSize.height) - (titleHeight + 24)
        guard available.isFinite, available >= 8 else { return minimumIconSide }
        let whole = Int(available)
        let stepped = whole < Int(maximumIconSide) ? whole & ~7 : Int(maximumIconSide)
        return max(CGFloat(stepped), minimumIconSide)
    }
}

/// The Classical title font: the 13 pt label UI font, which resolves to SF Medium with
/// monospaced digits.
enum ClassicalTitleFont {
    static let size: CGFloat = 13
    /// Text shadow: black at 0.2, offset (0, −1), blur 2, scaled for the backing scale.
    static let shadowAlpha: CGFloat = 0.2
    static let shadowOffset = CGSize(width: 0, height: -1)
    static let shadowBlur: CGFloat = 2

    /// The system UI font of type 105 at the title size, with monospaced digits.
    static var font: NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: .medium)
        guard let base = uiFontDescriptor(type: 105, size: size) else { return fallback }
        let descriptor = CTFontDescriptorCreateCopyWithFeature(base, kNumberSpacingType as CFNumber,
                                                               kMonospacedNumbersSelector as CFNumber)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }

    private typealias UIFontDescriptorFunction = @convention(c) (UInt32, CGFloat, CFString?) -> Unmanaged<CTFontDescriptor>?
    /// Core Text's `CTFontDescriptorCreateForUIType`, which the SDK does not declare; nil when absent.
    private static let createUIFontDescriptor: UIFontDescriptorFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CTFontDescriptorCreateForUIType") else { return nil }
        return unsafeBitCast(symbol, to: UIFontDescriptorFunction.self)
    }()

    private static func uiFontDescriptor(type: UInt32, size: CGFloat) -> CTFontDescriptor? {
        createUIFontDescriptor?(type, size, nil)?.takeRetainedValue()
    }

    /// `ceil(ascent + descent + leading)`, measured through Core Text.
    static var lineHeight: CGFloat {
        let font = font as CTFont
        return (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
    }
}
