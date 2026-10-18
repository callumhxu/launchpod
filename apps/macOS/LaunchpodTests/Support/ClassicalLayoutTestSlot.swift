import Foundation
@testable import Launchpod

/// A readable description of one root slot of a `ClassicalLayout`: an application by its index in
/// a test's identity list, or a folder with its title and pages of application indices.
/// Integer literals describe applications, so `[[0, 1]]` reads as a page holding apps 0 and 1.
nonisolated enum ClassicalLayoutTestSlot: Equatable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    case app(Int)
    case folder(String, [[Int]])

    init(integerLiteral value: Int) {
        self = .app(value)
    }

    var description: String {
        switch self {
        case let .app(index): "\(index)"
        case let .folder(title, pages): "folder(\(title): \(pages))"
        }
    }

    /// The root pages of `layout`, describing every identity by its index in `ids` (−1 when unknown).
    static func pages(of layout: ClassicalLayout, ids: [AppIdentity]) -> [[ClassicalLayoutTestSlot]] {
        func index(_ id: AppIdentity) -> Int { ids.firstIndex(of: id) ?? -1 }
        return layout.pages.map { page in
            page.map { item in
                switch item {
                case let .app(id): .app(index(id))
                case let .folder(folder): .folder(folder.title, folder.pages.map { $0.map(index) })
                }
            }
        }
    }
}
