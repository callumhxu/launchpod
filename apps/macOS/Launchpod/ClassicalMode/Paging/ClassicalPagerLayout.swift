import CoreGraphics

/// Where a `ClassicalPager` places its layers. `frame` is in the layer holding the pager; the strip
/// and dots are in the pager layer; the first page is in the strip, and later pages repeat
/// `pageWidth` apart. The same pager serves the root pages and the pages of an open folder.
struct ClassicalPagerLayout: Equatable, Sendable {
    var frame: CGRect
    var stripFrame: CGRect
    var dotsFrame: CGRect
    var firstPageFrame: CGRect
    var pageWidth: CGFloat
    var grid: ClassicalGridLayout
    /// Whether the pager layer and its strip clip their contents; an open folder clips through its mask instead.
    var clipsToBounds: Bool

    init(frame: CGRect, stripFrame: CGRect, dotsFrame: CGRect, firstPageFrame: CGRect, pageWidth: CGFloat,
         grid: ClassicalGridLayout, clipsToBounds: Bool) {
        self.frame = frame
        self.stripFrame = stripFrame
        self.dotsFrame = dotsFrame
        self.firstPageFrame = firstPageFrame
        self.pageWidth = pageWidth
        self.grid = grid
        self.clipsToBounds = clipsToBounds
    }

    /// The root pages: the pager fills the content frame and its strip starts above the bottom
    /// margin; pages sit one screen width apart.
    init(geometry: ClassicalSpringboardGeometry) {
        let content = geometry.contentFrame
        self.init(frame: content,
                  stripFrame: CGRect(x: 0, y: geometry.margins.bottom, width: content.width,
                                     height: content.height - geometry.margins.bottom),
                  dotsFrame: ClassicalPageDotsLayout.bandFrame(for: geometry).offsetBy(dx: 0, dy: -content.minY),
                  firstPageFrame: geometry.pageFrame.offsetBy(dx: -content.minX, dy: -geometry.pageFrame.minY),
                  pageWidth: geometry.screenSize.width, grid: geometry.grid, clipsToBounds: true)
    }
}
