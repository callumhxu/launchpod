import CoreFoundation
import Foundation

/// Orders automatically placed Classical applications with known system applications first.
nonisolated enum ClassicalLayoutTitleOrder {
    static func sorted(_ records: [AppRecord]) -> [AppRecord] {
        records.sorted { first, second in
            let firstIsSystem = hasSystemPriority(first)
            let secondIsSystem = hasSystemPriority(second)
            if firstIsSystem != secondIsSystem { return firstIsSystem }
            return lessThan(first.metadata.displayName, second.metadata.displayName)
        }
    }

    private static func hasSystemPriority(_ record: AppRecord) -> Bool {
        if let bundleID = record.metadata.knownBundleIdentifier,
           ClassicalInitialLayout.templateBundleIDs.contains(bundleID) { return true }
        return record.metadata.bundleURL.path.hasPrefix("/System/")
    }

    static func lessThan(_ first: String, _ second: String) -> Bool {
        let first = first as CFString
        let options: CFStringCompareFlags = [.compareCaseInsensitive, .compareLocalized, .compareNumerically]
        return CFStringCompareWithOptions(first, second as CFString,
                                          CFRangeMake(0, CFStringGetLength(first)), options) == .compareLessThan
    }
}
