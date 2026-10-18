import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Launchpod

/// The title a new Classical folder receives from its target application.
final class ClassicalLayoutFolderTests: XCTestCase {
    /// The target's category, named by the system's localized description of the category type.
    func testDefaultTitleIsTheTargetsCategoryName() throws {
        let utilities = try XCTUnwrap(UTType("public.app-category.utilities")?.localizedDescription)
        XCTAssertEqual(ClassicalLayoutFolder.defaultTitle(categoryIdentifier: "public.app-category.utilities",
                                                          locale: Locale(identifier: "en")), utilities)
        XCTAssertNotEqual(utilities, "Untitled")
        let developerTools = try XCTUnwrap(UTType("public.app-category.developer-tools")?.localizedDescription)
        XCTAssertEqual(ClassicalLayoutFolder.defaultTitle(categoryIdentifier: "public.app-category.developer-tools",
                                                          locale: Locale(identifier: "en")), developerTools)
    }

    /// No category, or a category the system cannot name, falls back to "Untitled" in the app's language.
    func testMissingOrUnknownCategoryFallsBackToLocalizedUntitled() {
        for language in CatalogTestSupport.locales {
            let title = CatalogTestSupport.text("Untitled", locale: language)
            let locale = Locale(identifier: language)
            XCTAssertEqual(ClassicalLayoutFolder.defaultTitle(categoryIdentifier: nil, locale: locale), title, language)
        }
        let english = Locale(identifier: "en")
        for unknown in ["public.app-category.bogus", "com.example.unknown", ""] {
            XCTAssertEqual(ClassicalLayoutFolder.defaultTitle(categoryIdentifier: unknown, locale: english), "Untitled",
                           unknown)
        }
    }

    /// A saved folder title may be any text but the empty string.
    func testDecodingRejectsOnlyAnEmptyTitle() throws {
        let app = AppIdentity()
        let spaced = ClassicalLayoutFolder(title: "  ", pages: [[app]])
        XCTAssertNoThrow(try spaced.validate())
        let decoded = try JSONDecoder().decode(ClassicalLayoutFolder.self, from: JSONEncoder().encode(spaced))
        XCTAssertEqual(decoded.title, "  ")
        let empty = ClassicalLayoutFolder(title: "", pages: [[app]])
        XCTAssertThrowsError(try empty.validate())
        XCTAssertThrowsError(try JSONDecoder().decode(ClassicalLayoutFolder.self, from: JSONEncoder().encode(empty)))
    }

    func testDirectoryOtherTitleStatePersistsUntilUserRenamesTheFolder() throws {
        let app = AppIdentity()
        let folder = ClassicalLayoutFolder(title: "Foo (Other)", pages: [[app]], usesDefaultTitle: true,
                                           directoryOtherBaseTitle: "Foo")
        let restored = try JSONDecoder().decode(ClassicalLayoutFolder.self, from: JSONEncoder().encode(folder))
        XCTAssertEqual(restored, folder)
        XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: restored.id, title: restored.title,
                                                          usesDefaultTitle: restored.usesDefaultTitle,
                                                          locale: Locale(identifier: "en"),
                                                          directoryOtherBaseTitle: restored.directoryOtherBaseTitle),
                       "Foo (Other)")

        var layout = try ClassicalLayout(pages: [[.folder(restored)]])
        XCTAssertTrue(layout.renameFolder(restored.id, to: "My Apps"))
        let renamed = try XCTUnwrap(layout.folders.first)
        XCTAssertEqual(renamed.title, "My Apps")
        XCTAssertFalse(renamed.usesDefaultTitle)
        XCTAssertNil(renamed.directoryOtherBaseTitle)
        XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: renamed.id, title: renamed.title,
                                                          usesDefaultTitle: renamed.usesDefaultTitle,
                                                          locale: Locale(identifier: "fr"),
                                                          directoryOtherBaseTitle: renamed.directoryOtherBaseTitle),
                       "My Apps", "A user title no longer follows the generated suffix")
    }

    func testDirectoryOtherSuffixUsesTheSelectedLanguage() {
        for language in CatalogTestSupport.locales {
            let title = CatalogTestSupport.format("%@ (Other)", locale: language, argument: "Foo")
            XCTAssertEqual(ClassicalLayoutFolder.displayTitle(for: .init(), title: "Foo (Other)",
                                                          usesDefaultTitle: true, locale: Locale(identifier: language),
                                                          directoryOtherBaseTitle: "Foo"),
                           title, language)
        }
    }
}
