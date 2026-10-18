import AppKit

/// Everything around the Classical page that depends on the Dock: which display to open on, the
/// Dock reserve, temporary reveal and hiding while a folder is open, and the paged cells. The window controller keeps the window,
/// animation and focus lifecycle.
@MainActor
final class ClassicalPagePresenter {
    /// The applications shown on the page; nil leaves the content area empty.
    var content: ClassicalPageContent?
    let springboard = ClassicalSpringboard()
    let keyboard: ClassicalKeyboard
    var pager: ClassicalPager { springboard.pager }
    /// Rows and columns for each presentation, from Launchpod's settings.
    var gridDimensions: @MainActor () -> (rows: Int, columns: Int) = { ClassicalGridPreference.dimensions() }
    /// Whether Classical folders use the glass appearance, from Launchpod's settings.
    var folderGlass: @MainActor () -> Bool = { ClassicalFolderGlassPreference.isEnabled() }
    /// The language for the search placeholder and "No Results".
    var locale: @MainActor () -> Locale = { .current }
    let dockReveal: ClassicalDockReveal
    /// Notifies the window owner when a folder changes the level the panel needs.
    var folderVisibilityChanged: (@MainActor (Bool) -> Void)?
    private let hidesDock: @MainActor () -> Bool
    private let dockDisplay: @MainActor () -> NSNumber?
    /// The screen size and scale the pages were last laid out for.
    private var laidOut: (size: CGSize, scale: CGFloat)?

    init(hidesDock: @escaping @MainActor () -> Bool = { ClassicalDockPreference.hidesDock() },
         dockReveal: ClassicalDockReveal? = nil,
         dockDisplay: @escaping @MainActor () -> NSNumber? = { ClassicalDockDisplay.dockScreen()?.displayNumber }) {
        self.hidesDock = hidesDock
        self.dockReveal = dockReveal ?? ClassicalDockReveal()
        self.dockDisplay = dockDisplay
        keyboard = ClassicalKeyboard(springboard: springboard)
        springboard.folders.locale = { [weak self] in self?.locale() ?? .current }
        // An open folder lets the Dock auto-hide and reappear when the pointer reaches its edge.
        springboard.folders.visibilityChanged = { [weak self] shown in
            guard let self else { return }
            if shown {
                keyboard.folderWillOpen()
                self.dockReveal.hideForFolder()
            } else {
                self.dockReveal.endFolderHide()
            }
            self.folderVisibilityChanged?(shown)
        }
    }

    /// The selected covering level, except while a folder needs the Dock to remain revealable.
    func windowLevel() -> NSWindow.Level {
        NSWindow.Level(rawValue: ClassicalDockPreference.windowLevel(
            hidesDock: hidesDock() && !springboard.folders.isActive))
    }

    /// Sets `window`'s level to `windowLevel()`, except while an application is dragged out of it,
    /// which keeps the level the drag chose.
    func updateLevel(of window: NSWindow?) {
        guard let window, let content = window.contentView as? ClassicalContentView,
              !content.isExternalDragging else { return }
        window.level = windowLevel()
    }

    /// Routes `view`'s pointer and key handling to this presenter's pages and keyboard.
    func connect(_ view: ClassicalContentView) {
        view.pager = pager
        view.keyboard = keyboard
        view.springboard = springboard
    }

    /// The launcher opens on the Dock's display; otherwise the pointer's.
    func screen() -> NSScreen? {
        let dockScreen = dockDisplay().flatMap { number in NSScreen.screens.first { $0.displayNumber == number } }
        let pointerScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        return dockScreen ?? pointerScreen ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// True when the Dock is known to be on a display other than `displayNumber`; the launcher then
    /// closes and the next presentation opens on the new display.
    func dockLeft(display displayNumber: NSNumber?) -> Bool {
        guard let dock = dockDisplay() else { return false }
        return dock != displayNumber
    }

    /// Lays the pages out on `screen`. On entry an auto-hiding Dock is revealed first so the pages
    /// reserve it, unless the user covers the Dock.
    func present(on screen: NSScreen, in contentLayer: CALayer, view: NSView, revealingDock: Bool) {
        // Hiding the Dock for a folder changes only the visible frame; laying out again would close
        // the folder, so the pages keep the layout the folder opened over.
        let size = screen.frame.size, scale = screen.backingScaleFactor
        if springboard.folders.isActive, let laidOut, laidOut.size == size, laidOut.scale == scale { return }
        laidOut = (size, scale)
        let coversDock = hidesDock()
        if revealingDock, !coversDock { dockReveal.reveal() }
        guard let content else { return }
        let grid = gridDimensions()
        let geometry = ClassicalSpringboardGeometry(screenSize: screen.frame.size,
                                                    dock: .init(screen: screen, hidesDock: coversDock,
                                                                revealed: dockReveal.revealedMetrics),
                                                    notchHeight: screen.safeAreaInsets.top,
                                                    rows: grid.rows, columns: grid.columns)
        let rightToLeft = NSApp.userInterfaceLayoutDirection == .rightToLeft
        let locale = self.locale()
        springboard.layoutDidChange = content.commit
        springboard.folderDragDidChange = content.commitFolderDrag
        springboard.folderTitleLocale = { locale }
        springboard.folderRenamed = content.renameFolder
        springboard.folders.accessibilityParent = view
        springboard.deferredRefreshNeeded = { [weak self] in self?.refreshRecords() }
        springboard.show(pages: localizedPages(content.pages(geometry.grid.capacity), locale: locale), geometry: geometry,
                         scale: screen.backingScaleFactor, rightToLeft: rightToLeft,
                         noResultsText: String(localized: LocalizedStringResource("No Results", locale: locale)),
                         icon: content.icon)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.addSublayer(pager.layer)
        CATransaction.commit()
        keyboard.contentView = view
        keyboard.field.placeholder = String(localized: LocalizedStringResource("Search", locale: locale))
        keyboard.field.place(in: contentLayer, view: view, frame: geometry.searchFieldFrame,
                             scale: screen.backingScaleFactor, rightToLeft: rightToLeft,
                             usesGlass: springboard.folderGlassEnabled)
    }

    /// Refreshes records without replacing the search editor or changing its focus and geometry.
    func refreshRecords() {
        guard let content else { return }
        springboard.refresh(pages: localizedPages(content.pages(springboard.capacity), locale: locale()))
    }

    /// Prepares catalog icons while the launcher is hidden, using its last laid-out icon sizes.
    func prepareRecords() {
        guard let content else { return }
        springboard.prepare { content.pages(springboard.capacity) }
    }

    private func localizedPages(_ pages: [[ClassicalPageItem]], locale: Locale) -> [[ClassicalPageItem]] {
        pages.map { page in
            page.map { item in
                guard case var .folder(folder) = item else { return item }
                folder.title = ClassicalLayoutFolder.displayTitle(for: folder.id, title: folder.title,
                                                                  usesDefaultTitle: folder.usesDefaultTitle,
                                                                  locale: locale,
                                                                  directoryOtherBaseTitle: folder.directoryOtherBaseTitle)
                return .folder(folder)
            }
        }
    }

    /// The presentation left the screen: the Dock returns to auto-hiding.
    func end() {
        pager.cancelInteraction()
        keyboard.reset()
        dockReveal.restore()
    }

    func stop() {
        pager.cancelInteraction()
        pager.cancelIconLoads()
        keyboard.reset()
        dockReveal.restore()
    }
}
