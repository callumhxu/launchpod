import Foundation

/// Whether applications on the Classical pages may be deleted, as their delete badges show.
/// Answers are kept until `removeAll()`, which the springboard calls whenever its pages are refreshed.
@MainActor
final class ClassicalDeletabilityCache {
    /// Replaceable in tests: whether an application may be deleted.
    var isDeletable: (AppRecord) -> Bool = { ClassicalDeletability.isDeletable($0.metadata.bundleURL) }
    private var answers: [AppIdentity: Bool] = [:]

    func canDelete(_ record: AppRecord) -> Bool {
        if let known = answers[record.id] { return known }
        let value = isDeletable(record)
        answers[record.id] = value
        return value
    }

    func removeAll() {
        answers.removeAll()
    }
}
