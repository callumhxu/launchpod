import Foundation

/// Classical search term matching. All comparisons are case-insensitive prefix tests.
///
/// A title matches when the term prefixes the whole title, any word of it, the initials of its
/// leading words, or the title with spaces removed. Words are the localized word ranges, split
/// again at lowercase-to-uppercase boundaries ("FaceTime" → "Face", "Time"), with runs of single
/// capital letters joined back together. A title that fails is tried once more in lowercase, and
/// an application also matches by its bundle file name when that differs from its title.
nonisolated enum ClassicalSearchMatcher {
    static func matches(_ record: AppRecord, term: String) -> Bool {
        // Unresolved applications stay on their pages but are excluded from search.
        guard record.isMissing != true, record.source.isOnline != false else { return false }
        return matches(title: record.metadata.displayName,
                       fileName: record.metadata.bundleURL.deletingPathExtension().lastPathComponent, term: term)
    }

    static func matches(title: String, fileName: String?, term: String) -> Bool {
        guard !term.isEmpty else { return false }
        if matchesTitle(title, term: term) { return true }
        guard let fileName, fileName != title else { return false }
        return matchesTitle(fileName, term: term)
    }

    static func matchesTitle(_ title: String, term: String) -> Bool {
        matches(title, term: term) || matches(title.lowercased(), term: term)
    }

    /// One pass of the word block over `string`.
    static func matches(_ string: String, term: String) -> Bool {
        if hasPrefix(string, term) { return true }
        let words = self.words(in: string)
        if words.contains(where: { hasPrefix($0, term) }) { return true }
        let compactTerm = term.replacingOccurrences(of: " ", with: "")
        let characters = compactTerm.map(String.init)
        if characters.count >= 2, characters.count <= words.count,
           zip(words, characters).allSatisfy({ hasPrefix($0, $1) }) {
            return true
        }
        if hasPrefix(string, compactTerm) { return true }
        return hasPrefix(string.replacingOccurrences(of: " ", with: ""), compactTerm)
    }

    static func words(in string: String) -> [String] {
        var split: [String] = []
        string.enumerateSubstrings(in: string.startIndex..., options: [.byWords, .localized]) { word, _, _, _ in
            guard let word else { return }
            let spaced = word.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            split += spaced.isEmpty ? [word] : spaced.components(separatedBy: " ")
        }
        var words: [String] = []
        var capitals = ""
        for word in split {
            if word.count == 1, word.rangeOfCharacter(from: .uppercaseLetters) != nil {
                capitals += word
                continue
            }
            if !capitals.isEmpty {
                words.append(capitals)
                capitals = ""
            }
            words.append(word)
        }
        if !capitals.isEmpty { words.append(capitals) }
        return words
    }

    /// `rangeOfString:options:` with anchored, case-insensitive search found at location 0.
    private static func hasPrefix(_ string: String, _ prefix: String) -> Bool {
        guard !prefix.isEmpty else { return false }
        return string.range(of: prefix, options: [.anchored, .caseInsensitive]) != nil
    }
}
