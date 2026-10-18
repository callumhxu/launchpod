import Foundation
import UniformTypeIdentifiers

/// A Classical folder: a titled, ordered list of pages of applications, placed in one root slot.
/// Folders hold only applications, never other folders. A folder inside a `ClassicalLayout` always
/// has at least one application and no empty page; the layout enforces this.
nonisolated struct ClassicalLayoutFolder: Codable, Hashable, Sendable, Identifiable {
    /// The folder's stable persistent identity, independent of its title and position.
    nonisolated struct ID: Hashable, Codable, Sendable {
        let rawValue: UUID

        static let defaultOther = ID(rawValue: UUID(uuid: (0x19, 0x2d, 0xa7, 0x94,
                                                           0xa1, 0x8a, 0x44, 0xa3,
                                                           0x9b, 0x41, 0xf7, 0xe5,
                                                           0x6c, 0x14, 0x82, 0xa9)))
        static let defaultGames = ID(rawValue: UUID(uuid: (0x52, 0x4f, 0xb1, 0x21,
                                                           0x7c, 0x09, 0x40, 0x51,
                                                           0xb2, 0x8e, 0x64, 0x5f,
                                                           0x6e, 0x13, 0xd4, 0x75)))
        static let defaultTestFlight = ID(rawValue: UUID(uuid: (0x10, 0x4e, 0x54, 0x4b,
                                                                0x7d, 0x35, 0x46, 0x5b,
                                                                0x86, 0xbc, 0x6a, 0x4b,
                                                                0x2e, 0xed, 0xc5, 0x19)))
        static let defaultServer = ID(rawValue: UUID(uuid: (0x89, 0xa9, 0x8f, 0x6c,
                                                            0x4b, 0x91, 0x49, 0x5d,
                                                            0xb4, 0xe2, 0x2d, 0x43,
                                                            0xaf, 0x03, 0xc7, 0x11)))
        static let defaultAppleInternal = ID(rawValue: UUID(uuid: (0x9a, 0x10, 0x91, 0x8b,
                                                                   0x9e, 0xd2, 0x4c, 0x69,
                                                                   0xb1, 0xb3, 0xe0, 0x36,
                                                                   0x8a, 0x20, 0xc7, 0x5e)))

        init(rawValue: UUID = UUID()) {
            self.rawValue = rawValue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            rawValue = try container.decode(UUID.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    enum ValidationError: Error {
        case emptyTitle
        case emptyFolder
        case emptyPage
    }

    let id: ID
    /// The saved title; built-in titles are localized for presentation. Never empty inside a layout.
    var title: String
    /// Whether the canonical title is localized when shown; a user rename clears this.
    var usesDefaultTitle: Bool
    /// The source directory's display name for a generated “Other” sibling; nil for other folders.
    var directoryOtherBaseTitle: String?
    /// The folder's pages, each holding at most the main grid's capacity once reconciled.
    var pages: [[AppIdentity]]

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case usesDefaultTitle
        case directoryOtherBaseTitle
        case pages
    }

    init(id: ID = ID(), title: String, pages: [[AppIdentity]], usesDefaultTitle: Bool = false,
         directoryOtherBaseTitle: String? = nil) {
        self.id = id
        self.title = title
        self.pages = pages
        self.usesDefaultTitle = usesDefaultTitle
        self.directoryOtherBaseTitle = directoryOtherBaseTitle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(ID.self, forKey: .id),
                  title: try container.decode(String.self, forKey: .title),
                  pages: try container.decode([[AppIdentity]].self, forKey: .pages),
                  usesDefaultTitle: try container.decode(Bool.self, forKey: .usesDefaultTitle),
                  directoryOtherBaseTitle: try container.decodeIfPresent(String.self,
                                                                        forKey: .directoryOtherBaseTitle))
        try validate()
    }

    /// The folder's applications in page order.
    var identities: [AppIdentity] { pages.flatMap { $0 } }

    /// The built-in folder uses a stable saved title; user-renamed folders show their saved title.
    static func displayTitle(for id: ID, title: String, usesDefaultTitle: Bool, locale: Locale,
                             directoryOtherBaseTitle: String? = nil) -> String {
        guard usesDefaultTitle else { return title }
        if let directoryOtherBaseTitle {
            let format = String(localized: LocalizedStringResource("%@ (Other)", locale: locale))
            return String(format: format, locale: locale, arguments: [directoryOtherBaseTitle])
        }
        switch id {
        case .defaultOther:
            return String(localized: LocalizedStringResource("Other", locale: locale))
        case .defaultGames:
            return String(localized: LocalizedStringResource("Games", locale: locale))
        case .defaultTestFlight:
            return String(localized: LocalizedStringResource("TestFlight", locale: locale))
        case .defaultServer:
            return String(localized: LocalizedStringResource("Server", locale: locale))
        case .defaultAppleInternal:
            return String(localized: LocalizedStringResource("Apple Internal", locale: locale))
        default:
            return title
        }
    }

    /// Throws when the title is empty, a page is empty, or the folder holds no application.
    func validate() throws {
        guard !Self.isEmptyTitle(title) else { throw ValidationError.emptyTitle }
        guard !pages.isEmpty else { throw ValidationError.emptyFolder }
        guard pages.allSatisfy({ !$0.isEmpty }) else { throw ValidationError.emptyPage }
    }

    /// Whether `title` is unusable as a folder title: only the empty string is; a title of spaces is kept.
    static func isEmptyTitle(_ title: String) -> Bool {
        title.isEmpty
    }

    /// The title a new folder receives from its target application: the localized name of the
    /// target's application category, otherwise "Untitled" in `locale`.
    ///
    /// The category name comes from `UTType.localizedDescription`, which follows the process's
    /// preferred languages rather than `locale`; no public API names a category in another language.
    static func defaultTitle(categoryIdentifier: String?, locale: Locale) -> String {
        if let categoryIdentifier, let name = UTType(categoryIdentifier)?.localizedDescription, !isEmptyTitle(name) {
            return name
        }
        return String(localized: LocalizedStringResource("Untitled", locale: locale))
    }
}
