import Foundation
import XCTest
@testable import Launchpod

/// How one root slot is saved: an application as its identity string and a folder as an object.
final class ClassicalLayoutItemTests: XCTestCase {
    func testFolderFreeLayoutKeepsTheIdentityStringFormat() throws {
        let first = UUID().uuidString
        let second = UUID().uuidString
        let saved = Data(#"{"schemaVersion":1,"pages":[["\#(first)","\#(second)"]],"excludedIDs":[],"excludedObservedAbsentIDs":[],"appReferences":[]}"#.utf8)
        let layout = try JSONDecoder().decode(ClassicalLayout.self, from: saved)
        XCTAssertEqual(layout.pages, [[.app(AppIdentity(rawValue: try XCTUnwrap(UUID(uuidString: first)))),
                                       .app(AppIdentity(rawValue: try XCTUnwrap(UUID(uuidString: second))))]])

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["pages"] as? [[String]], [[first, second]])
    }

    func testFolderEncodesAsAnObjectWithItsIDTitleAndPages() throws {
        let folderID = UUID()
        let apps = [AppIdentity(), AppIdentity(), AppIdentity()]
        let folder = ClassicalLayoutFolder(id: ClassicalLayoutFolder.ID(rawValue: folderID), title: "Work",
                                           pages: [[apps[0], apps[1]], [apps[2]]])
        let item = ClassicalLayoutItem.folder(folder)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["id", "title", "usesDefaultTitle", "pages"])
        XCTAssertEqual(json["id"] as? String, folderID.uuidString)
        XCTAssertEqual(json["title"] as? String, "Work")
        XCTAssertEqual(json["usesDefaultTitle"] as? Bool, false, "A user-titled folder shows its saved title")
        XCTAssertEqual(json["pages"] as? [[String]], [[apps[0].rawValue.uuidString, apps[1].rawValue.uuidString],
                                                       [apps[2].rawValue.uuidString]])
        XCTAssertEqual(try JSONDecoder().decode(ClassicalLayoutItem.self, from: JSONEncoder().encode(item)), item)

        let app = ClassicalLayoutItem.app(apps[0])
        XCTAssertEqual(String(data: try JSONEncoder().encode(app), encoding: .utf8),
                       "\"\(apps[0].rawValue.uuidString)\"")
    }
}
