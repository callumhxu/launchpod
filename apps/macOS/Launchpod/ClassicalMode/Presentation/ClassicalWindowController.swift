import AppKit
import QuartzCore

@MainActor
final class ClassicalWindowController: NSWindowController, NSWindowDelegate, LauncherPlaceholderPresenting {
    var onDismiss: (@MainActor () -> Void)?
    var openSettings: (@MainActor () -> Void)? {
        didSet { (window as? ClassicalPanel)?.launcherContentView.openSettings = openSettings }
    }
    var showsMenuBarItem: @MainActor () -> Bool = { true } {
        didSet { (window as? ClassicalPanel)?.launcherContentView.showsMenuBarItem = showsMenuBarItem }
    }
    /// Routes a user dismissal into the application's visibility request state.
    var onDismissRequested: (@MainActor () -> Void)?
    var retainsFocusForOwnedInteraction: (@MainActor () -> Bool)?
    /// Submits the open request for an application and the display the launcher is on. Replaceable
    /// in tests; the default is the LaunchServices call.
    var openApplication: @MainActor (AppRecord, CGDirectDisplayID?) -> Void = { record, display in
        ClassicalApplicationOpener.open(record.metadata.bundleURL, display: display)
    }
    /// Whether the bundle is still present; a missing application is neither opened nor dismissed.
    var canOpenApplication: @MainActor (AppRecord) -> Bool = { ClassicalApplicationOpener.canOpen($0.metadata.bundleURL) }
    /// The language for the search placeholder and "No Results".
    var locale: @MainActor () -> Locale {
        get { page.locale }
        set { page.locale = newValue }
    }
    /// The applications shown on the page; nil leaves the content area empty.
    var pageContent: ClassicalPageContent? {
        get { page.content }
        set {
            page.content = newValue
            (window as? ClassicalPanel)?.launcherContentView.deletion.didRemoveRecord = newValue?.didDelete
        }
    }
    var slowMotionAllowed: @MainActor () -> Bool = {
        UserDefaults(suiteName: "com.apple.dock").map(ClassicalAnimationParameters.slowMotionAllowed(in:)) ?? false
    }
    var shiftKeyDown: @MainActor () -> Bool = { NSEvent.modifierFlags.contains(.shift) }
    var isVisible: Bool { window?.isVisible == true }

    private let presentError: @MainActor (Error) -> Void
    private let stage: ClassicalDesktopStage
    private var menuBarVisibility: ClassicalMenuBarVisibility { stage.menuBarVisibility }
    private let page: ClassicalPagePresenter
    private var revision = UUID()
    private var targetIsVisible = false
    private var isStopped = false
    private var isChangingVisibility = false
    private var enterCompleted = false
    private var animationInput = (slowMotionAllowed: false, shiftKeyDown: false)
    private var completions: [@MainActor (Bool) -> Void] = []

    init(desktopImage: (@MainActor (NSScreen) async throws -> CGImage)? = nil,
         presentError: @escaping @MainActor (Error) -> Void = { NSApp.presentError($0) },
         menuBarVisibility: ClassicalMenuBarVisibility? = nil,
         hidesDock: @escaping @MainActor () -> Bool = { ClassicalDockPreference.hidesDock() },
         dockReveal: ClassicalDockReveal? = nil,
         dockDisplay: @escaping @MainActor () -> NSNumber? = { ClassicalDockDisplay.dockScreen()?.displayNumber }) {
        self.presentError = presentError
        page = ClassicalPagePresenter(hidesDock: hidesDock, dockReveal: dockReveal, dockDisplay: dockDisplay)
        stage = ClassicalDesktopStage(desktopImage: desktopImage,
                                      menuBarVisibility: menuBarVisibility ?? ClassicalMenuBarVisibility())
        let panel = ClassicalPanel.makeLauncherPanel()
        let content = panel.launcherContentView
        super.init(window: panel)
        panel.delegate = self
        content.dismiss = { [weak self] in self?.dismiss() }
        content.menuLocale = { [weak self] in self?.locale() ?? .current }
        page.connect(content)
        page.folderVisibilityChanged = { [weak self] _ in self?.updateWindowLevel() }
        content.launch = { [weak self] record in self?.open(record) }
        content.deletion.locale = { [weak self] in self?.locale() ?? .current }
        content.deletion.restoreFocus = { [weak self] in
            guard let self, self.targetIsVisible, !self.isStopped, let window = self.window, window.isVisible else { return }
            window.makeKey()
        }
        content.externalDragDidEnd = { [weak self] in self?.updateWindowLevel() }
        page.keyboard.dismiss = { [weak self] in self?.dismiss() }
        page.keyboard.launch = { [weak self] record in self?.open(record) }
        panel.dismiss = { [weak self] in self?.dismiss() }
        panel.alphaDidChange = { [weak self] oldAlpha, alpha in self?.windowAlphaChanged(from: oldAlpha, to: alpha) }
        panel.didOrderOut = { [weak self] in self?.windowOrderedOut() }
        stage.desktopPictureDidChange = { [weak self] in self?.desktopPictureChanged() }
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    /// Updates an existing presentation without reopening it or restarting its animation.
    func refreshApplications(invalidatingIcons affectedIDs: Set<AppIdentity>) {
        guard !isStopped else { return }
        page.springboard.invalidateIcons(for: affectedIDs)
        guard targetIsVisible, let window, window.isVisible, window.alphaValue > 0 else {
            page.prepareRecords()
            return
        }
        page.refreshRecords()
    }

    /// Fades a changed wallpaper in while shown.
    func desktopPictureChanged() {
        guard targetIsVisible, !isStopped, isVisible, stage.layers?.desktopLayer != nil, let screen = stage.screen else { return }
        stage.crossfadeDesktop(on: screen, isCurrent: isCurrent(revision))
    }

    /// Whether work started for `request` still applies.
    private func isCurrent(_ request: UUID) -> @MainActor () -> Bool {
        { [weak self] in self.map { $0.revision == request && !$0.isStopped } ?? false }
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        ClassicalLauncherDiagnostics.stopObserving(window)
        stage.cancelImageLoad()
        menuBarVisibility.stopFollowing()
        stage.tearDown()
        window?.delegate = nil
        window?.close()
        menuBarVisibility.restore()
        page.stop()
    }

    func setVisible(_ visible: Bool, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        setVisible(visible, suppressSlowMotion: false, completion: completion)
    }

    func setVisible(_ visible: Bool, suppressSlowMotion: Bool,
                    completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        let endDiagnostics = ClassicalLauncherDiagnostics.beginVisibilityRequest(visible, window: window)
        defer { endDiagnostics() }
        guard !isStopped, let window else {
            completion(false)
            return
        }
        if visible == targetIsVisible {
            if visible, window.isVisible {
                isChangingVisibility = true
                stage.coverMenuBar(in: window)
                window.orderFrontRegardless()
                window.makeKey()
                window.makeFirstResponder(window.initialFirstResponder)
                isChangingVisibility = false
            } else if !visible, !window.isVisible {
                menuBarVisibility.restore()
            }
            if !completions.isEmpty {
                completions.append(completion)
            } else {
                completion(visible ? window.isVisible && window.alphaValue > 0 && window.isKeyWindow && enterCompleted
                           && hasLauncherFocus(window) : !window.isVisible)
            }
            return
        }
        revision = UUID()
        let request = revision
        targetIsVisible = visible
        animationInput = (slowMotionAllowed() && !suppressSlowMotion, shiftKeyDown())
        stage.cancelImageLoad()
        let superseded = completions
        completions = [completion]
        superseded.forEach { $0(false) }
        guard revision == request, !isStopped else { return }
        if visible {
            beginShowing(request: request)
        } else {
            beginHiding(request: request)
        }
    }

    private func beginShowing(request: UUID, screen selectedScreen: NSScreen? = nil) {
        enterCompleted = false
        // An interrupted exit belongs to the previous window presentation.
        if let layers = stage.layers, !layers.isVisible {
            stage.tearDown()
            orderOut()
        }
        guard let screen = selectedScreen ?? page.screen() else {
            failShowing(request: request, error: PresentationError.noScreen)
            return
        }
        stage.screenIdentifier = screen.displayNumber
        stage.loadImage(for: screen, isCurrent: isCurrent(request)) { [weak self] result in
            switch result {
            case let .success(image): self?.install(image: image, screen: screen, request: request)
            case let .failure(error): self?.failShowing(request: request, error: error)
            }
        }
    }

    private func install(image: CGImage, screen: NSScreen, request: UUID) {
        guard let window, let content = window.contentView, let host = content.layer else {
            failShowing(request: request, error: PresentationError.missingContent)
            return
        }
        isChangingVisibility = true
        defer { isChangingVisibility = false }
        window.setFrame(screen.frame, display: false)
        let (layers, desktop) = stage.build(image: image, screen: screen)
        // One reading of the setting per presentation: the glass stage, pages and search field agree.
        page.springboard.folderGlassEnabled = page.folderGlass()
        (content as? ClassicalContentView)?.installGlassStage(rootLayer: layers.layer, contentLayer: layers.contentLayer)
        page.present(on: screen, in: layers.contentLayer, view: content, revealingDock: true)
        page.keyboard.field.setShowsTextField(false)
        updateWindowLevel()
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(content)
        ClassicalLauncherDiagnostics.didMakeKey(window)
        layers.show(in: host, desktopLayer: desktop, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    slowMotionAllowed: animationInput.slowMotionAllowed,
                    shiftKeyDown: animationInput.shiftKeyDown) { [weak self] in
            guard let self, self.revision == request, self.targetIsVisible, !self.isStopped else { return }
            self.enterCompleted = true
            self.page.keyboard.field.setShowsTextField(true)
            self.menuBarVisibility.stopFollowing()
            self.stage.coverMenuBar(in: self.window)
            self.finishShowingIfFocused()
        }
        stage.followMenuBar(in: window)
        finishShowingIfFocused()
    }

    private func beginHiding(request: UUID) {
        page.keyboard.field.setShowsTextField(false)
        updateWindowLevel()
        guard let layers = stage.layers, layers.isVisible else {
            orderOut()
            finishRequest(!isVisible)
            return
        }
        layers.hide(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    slowMotionAllowed: animationInput.slowMotionAllowed,
                    shiftKeyDown: animationInput.shiftKeyDown,
                    scaledLayers: page.springboard.folders.panelLayers) { [weak self] in
            guard let self, self.revision == request, !self.targetIsVisible, !self.isStopped else { return }
            self.orderOut()
            self.finishRequest(!self.isVisible)
        }
        stage.followMenuBar(in: window)
    }

    private func finishShowingIfFocused() {
        guard targetIsVisible, enterCompleted, let window, window.isVisible, window.alphaValue > 0, window.isKeyWindow,
              let responder = window.initialFirstResponder else { return }
        // Typing in the search field keeps its focus; otherwise the content view takes it.
        if !page.keyboard.ownsFocus(in: window) {
            guard window.makeFirstResponder(responder), window.firstResponder === responder else { return }
        }
        ClassicalLauncherDiagnostics.didAcquireFocus(window)
        finishRequest(true)
    }

    private func failShowing(request: UUID, error: Error) {
        guard revision == request, !isStopped else { return }
        targetIsVisible = false
        stage.tearDown()
        orderOut()
        finishRequest(false)
        guard revision == request, !isStopped, !targetIsVisible else { return }
        onDismiss?()
        guard revision == request, !isStopped, !targetIsVisible else { return }
        presentError(error)
    }

    private func finishRequest(_ succeeded: Bool) {
        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0(succeeded) }
    }

    private func orderOut() {
        (window as? ClassicalPanel)?.launcherContentView.deletion.dismiss()
        let wasChanging = isChangingVisibility
        isChangingVisibility = true
        menuBarVisibility.stopFollowing()
        window?.orderOut(nil)
        menuBarVisibility.restore()
        page.end()
        (window as? ClassicalPanel)?.launcherContentView.removeGlassStage()
        updateWindowLevel()
        ClassicalLauncherDiagnostics.didOrderOut(window)
        isChangingVisibility = wasChanging
    }

    /// The open request is submitted without waiting for the application, the icon's open animation
    /// plays above the launcher, and the launcher starts closing at once.
    private func open(_ record: AppRecord) {
        guard targetIsVisible, !isStopped, canOpenApplication(record) else { return }
        openApplication(record, stage.screenIdentifier?.uint32Value)
        pageContent?.didOpen(record.id)
        if let host = window?.contentView?.layer, let cell = page.springboard.cell(for: record.id) {
            ClassicalOpenAnimation.play(icon: cell.iconLayer, in: host)
        }
        dismiss()
    }

    private func dismiss() {
        guard targetIsVisible, !isStopped else { return }
        if let onDismissRequested {
            onDismissRequested()
            return
        }
        setVisible(false) { [weak self] succeeded in
            guard succeeded, let self, !self.targetIsVisible else { return }
            self.onDismiss?()
        }
    }

    private func hasLauncherFocus(_ window: NSWindow) -> Bool {
        window.firstResponder === window.initialFirstResponder || page.keyboard.ownsFocus(in: window)
    }

    private func updateWindowLevel() {
        page.updateLevel(of: window)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        finishShowingIfFocused()
    }

    private func windowAlphaChanged(from oldAlpha: CGFloat, to alpha: CGFloat) {
        if alpha <= 0 {
            menuBarVisibility.restore()
        } else if targetIsVisible, !isStopped {
            if isVisible {
                stage.coverMenuBar(in: window)
                finishShowingIfFocused()
            } else if oldAlpha <= 0 {
                endPresentationImmediately()
            }
        }
    }

    private func windowOrderedOut() {
        guard !isChangingVisibility else { return }
        if targetIsVisible, !isStopped, (window?.alphaValue ?? 1) > 0 {
            endPresentationImmediately()
        } else {
            menuBarVisibility.restore()
        }
    }

    @objc private func screenParametersChanged() {
        guard targetIsVisible, !isStopped else { return }
        guard let screen = stage.screen else {
            endPresentationImmediately()
            return
        }
        if page.dockLeft(display: stage.screenIdentifier) {
            dismiss()
            return
        }
        stage.cancelImageLoad()
        let request = revision
        guard isVisible, let layers = stage.layers, layers.desktopLayer != nil else {
            beginShowing(request: request, screen: screen)
            return
        }
        window?.setFrame(screen.frame, display: true)
        stage.resize(to: screen, isCurrent: isCurrent(request)) { [weak self] error in
            self?.failShowing(request: request, error: error)
        }
        if let content = window?.contentView {
            page.present(on: screen, in: layers.contentLayer, view: content, revealingDock: false)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isChangingVisibility, isVisible, (window?.alphaValue ?? 0) > 0, window?.isKeyWindow != true,
              retainsFocusForOwnedInteraction?() != true,
              // The deletion popover and Finder's password prompt take key focus while the launcher stays open.
              (window as? ClassicalPanel)?.launcherContentView.deletion.isActive != true else { return }
        dismiss()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isChangingVisibility, !isStopped else { return }
        endPresentationImmediately()
    }

    private func endPresentationImmediately() {
        let wasTargetVisible = targetIsVisible
        revision = UUID()
        let request = revision
        targetIsVisible = false
        enterCompleted = false
        stage.cancelImageLoad()
        stage.tearDown()
        orderOut()
        finishRequest(!wasTargetVisible)
        guard revision == request, !isStopped, wasTargetVisible else { return }
        if let onDismissRequested {
            onDismissRequested()
        } else {
            onDismiss?()
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        NotificationCenter.default.removeObserver(self)
        ClassicalLauncherDiagnostics.didStop(window)
        revision = UUID()
        targetIsVisible = false
        updateWindowLevel()
        stage.cancelImageLoad()
        menuBarVisibility.stopFollowing()
        onDismiss = nil
        onDismissRequested = nil
        retainsFocusForOwnedInteraction = nil
        stage.tearDown()
        window?.delegate = nil
        window?.close()
        window = nil
        menuBarVisibility.restore()
        page.stop()
        finishRequest(false)
    }

    private enum PresentationError: Error {
        case noScreen
        case missingContent
    }
}
