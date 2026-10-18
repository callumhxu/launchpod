import Foundation
@testable import Launchpod

/// Holds the first completed directory scan until a test releases it.
actor PausingFirstScanScanner: ApplicationScanning {
    private let scanner = ApplicationScanner()
    private var continuation: CheckedContinuation<Void, Never>?
    private var shouldPause = true
    private(set) var isPaused = false
    private(set) var didReturn = false

    func scan(_ directory: ApplicationScan.Directory) async -> ApplicationScan {
        let result = await scanner.scan(directory)
        if shouldPause {
            shouldPause = false
            isPaused = true
            await withCheckedContinuation { continuation = $0 }
            isPaused = false
        }
        didReturn = true
        return result
    }

    func resume() {
        shouldPause = false
        continuation?.resume()
        continuation = nil
    }

    func isCurrent(_ scan: ApplicationScan) async -> Bool {
        await scanner.isCurrent(scan)
    }

    func isMissing(at url: URL) async -> Bool? {
        await scanner.isMissing(at: url)
    }
}
