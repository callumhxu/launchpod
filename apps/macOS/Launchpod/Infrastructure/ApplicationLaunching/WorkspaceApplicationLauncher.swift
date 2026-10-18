import AppKit

/// A Launchpod adapter that opens the selected installation through the workspace.
@MainActor
final class WorkspaceApplicationLauncher {
    typealias OpenApplication = @MainActor (
        URL,
        NSWorkspace.OpenConfiguration
    ) async throws -> NSRunningApplication

    private let openApplication: OpenApplication

    init(openApplication: @escaping OpenApplication = { url, configuration in
        try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }) {
        self.openApplication = openApplication
    }

    /// Every call submits one open request; the system may reuse that installation's process.
    /// Cancellation prevents submission only. Once submitted, this returns the system's result.
    func launch(_ metadata: AppMetadata) async throws -> NSRunningApplication {
        try Task.checkCancellation()
        let url = metadata.bundleURL
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        // Return launch errors to the caller; the system still controls Gatekeeper prompts.
        configuration.promptsUserIfNeeded = false

        return try await openApplication(url, configuration)
    }
}
