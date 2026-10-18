import Foundation

/// One slot of a Classical root page: an application or a folder.
///
/// An application is stored as its identity string and a folder as an object, so a page without
/// folders keeps the same encoding as a plain list of identities.
nonisolated enum ClassicalLayoutItem: Codable, Hashable, Sendable {
    case app(AppIdentity)
    case folder(ClassicalLayoutFolder)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(AppIdentity.self) {
            self = .app(id)
        } else {
            self = .folder(try container.decode(ClassicalLayoutFolder.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .app(id): try container.encode(id)
        case let .folder(folder): try container.encode(folder)
        }
    }

    /// The application in this slot, or nil for a folder.
    var app: AppIdentity? {
        guard case let .app(id) = self else { return nil }
        return id
    }

    /// The folder in this slot, or nil for an application.
    var folder: ClassicalLayoutFolder? {
        guard case let .folder(folder) = self else { return nil }
        return folder
    }

    /// Every application this slot holds: the application itself, or the folder's applications in page order.
    var identities: [AppIdentity] {
        switch self {
        case let .app(id): [id]
        case let .folder(folder): folder.identities
        }
    }
}
