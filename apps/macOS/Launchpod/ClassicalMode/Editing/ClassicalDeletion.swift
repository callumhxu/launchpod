import AppKit
import OSLog

/// Deleting an application from its badge: the confirmation panel, then the removal.
///
/// `uninstalld` rejects clients without the `com.apple.private.uninstalld.client` entitlement,
/// which only Apple can sign, so Launchpod asks Finder to move the bundle to the Trash; Finder
/// asks for an administrator password when the bundle belongs to root, as App Store applications
/// do. Deleting mode stays on, and the item leaves the page once the bundle is gone.
@MainActor
final class ClassicalDeletion {
    private static let log = Logger(subsystem: "app.joyx.launchpod", category: "ClassicalDeletion")

    weak var springboard: ClassicalSpringboard?
    var locale: @MainActor () -> Locale = { .current }
    /// Replaceable in tests: removes the bundle, throwing when it could not.
    var remove: @MainActor (URL) async throws -> Void = { url in
        ClassicalFinderTrash.yieldToAuthentication()
        try await ClassicalFinderTrash.moveToTrash(url)
    }
    /// Called when the panel closes and when a removal finishes, so the launcher can take key focus
    /// back from the popover and Finder's prompts.
    var restoreFocus: (@MainActor () -> Void)?
    /// Updates the persisted arrangement only after the bundle actually leaves its location.
    var didRemoveRecord: (@MainActor (AppIdentity) -> Void)?

    private(set) var panel: ClassicalDeletionPanel?
    private var removals = 0

    /// True while the panel is open or a removal runs: the launcher keeps itself open when another
    /// window, such as Finder's authentication prompt, takes key focus.
    var isActive: Bool { panel != nil || removals > 0 }
    var isPanelShown: Bool { panel != nil }

    func present(_ record: AppRecord, cell: ClassicalItemLayer, in view: NSView) {
        guard panel == nil, let host = view.layer else { return }
        let locale = locale()
        let icon = NSWorkspace.shared.icon(forFile: record.metadata.bundleURL.path)
        let panel = ClassicalDeletionPanel(
            record: record, icon: icon,
            message: ClassicalDeletionPanel.message(for: record.metadata.displayName, locale: locale),
            cancelTitle: String(localized: LocalizedStringResource("Cancel", locale: locale)),
            actionTitle: String(localized: LocalizedStringResource("Delete", locale: locale)))
        panel.onFinish = { [weak self] confirmed in self?.finish(record, confirmed: confirmed) }
        self.panel = panel
        panel.show(iconFrame: cell.iconLayer.convert(cell.iconLayer.bounds, to: host), in: view)
    }

    /// Keys go to the open panel; returns false when there is none.
    func keyDown(_ event: NSEvent) -> Bool {
        guard let panel else { return false }
        panel.handleKey(event)
        return true
    }

    /// Closes an open panel without deleting, as when the launcher closes.
    func dismiss() {
        panel?.cancel()
    }

    private func finish(_ record: AppRecord, confirmed: Bool) {
        panel = nil
        guard confirmed else {
            restoreFocus?()
            return
        }
        removals += 1
        let url = record.metadata.bundleURL
        Task { [weak self, remove] in
            do {
                try await remove(url)
                self?.didRemoveRecord?(record.id)
                self?.springboard?.removeRecord(record.id)
            } catch {
                Self.log.error("Deleting \(url.path, privacy: .public) failed: \(error, privacy: .public)")
                if !ClassicalFinderTrash.isCancellation(error) { NSSound.beep() }
            }
            guard let self else { return }
            self.removals -= 1
            self.restoreFocus?()
        }
    }
}

/// Moves a bundle to the Trash through Finder's `delete` Apple Event, which prompts for
/// authentication when the bundle is not writable by the user.
nonisolated enum ClassicalFinderTrash {
    /// The process that shows Finder's administrator password prompt.
    static let authenticationAgent = "com.apple.SecurityAgent"

    /// Clicking the panel's button makes Launchpod the active application, and since macOS 14 another
    /// application only takes key focus when the active one yields it; without this the password
    /// prompt appears without focus and Touch ID does not respond.
    @MainActor
    static func yieldToAuthentication() {
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: authenticationAgent)
    }

    /// Finder may wait on the password prompt; the event does not time out before the user answers.
    static let timeout: TimeInterval = 600

    static func moveToTrash(_ url: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEDelete),
                                               targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                               transactionID: AETransactionID(kAnyTransactionID))
            event.setParam(NSAppleEventDescriptor(fileURL: url), forKeyword: AEKeyword(keyDirectObject))
            let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
            if let code = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, code != 0 {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(code))
            }
        }.value
    }

    /// The user cancelled Finder's password prompt (`userCanceledErr`).
    static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSOSStatusErrorDomain && error.code == Int(userCanceledErr)
    }
}
