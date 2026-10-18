import AppKit
import XCTest
@testable import Launchpod

final class ClassicalSearchFieldTests: XCTestCase {
    /// A 250 × 25 field and a 52 × 19 placeholder.
    func testLoupeAndPlaceholderCentreWhenIdleAndMoveToTheLeadingEdge() {
        let layout = ClassicalSearchFieldLayout(bounds: CGRect(x: 0, y: 0, width: 250, height: 25),
                                                placeholderSize: CGSize(width: 52, height: 19), rightToLeft: false)
        XCTAssertEqual(layout.placeholderFrame(active: false), CGRect(x: 111, y: 4, width: 52, height: 19))
        XCTAssertEqual(layout.loupeFrame(active: false), CGRect(x: 91, y: 7, width: 12, height: 12))
        XCTAssertEqual(layout.placeholderFrame(active: true).minX, 27)
        XCTAssertEqual(layout.loupeFrame(active: true).minX, 7)
        XCTAssertEqual(layout.closeFrame, CGRect(x: 230, y: 6, width: 14, height: 14))

        let mirrored = ClassicalSearchFieldLayout(bounds: layout.bounds, placeholderSize: layout.placeholderSize, rightToLeft: true)
        XCTAssertEqual(mirrored.placeholderFrame(active: false).minX, 87)
        XCTAssertEqual(mirrored.loupeFrame(active: false).minX, 147)
        XCTAssertEqual(mirrored.loupeFrame(active: true).minX, 231)
        XCTAssertEqual(mirrored.placeholderFrame(active: true).maxX, 223)
        XCTAssertEqual(mirrored.closeFrame.minX, 6)
    }

    @MainActor
    func testTypedTextHidesThePlaceholderAndShowsTheClearButton() {
        let field = ClassicalSearchField()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        field.placeholder = "Search"
        field.place(in: CALayer(), view: view, frame: CGRect(x: 275, y: 500, width: 250, height: 25), scale: 2, rightToLeft: false,
                    usesGlass: false)
        XCTAssertFalse(field.placeholderLayer.isHidden)
        XCTAssertTrue(field.closeLayer.isHidden)
        XCTAssertEqual(field.placeholderLayer.foregroundColor?.alpha, 0.36)
        XCTAssertTrue(field.textField.isHidden, "The editor appears only once typing starts")
        field.activate()
        XCTAssertFalse(field.textField.isHidden)
        field.textField.stringValue = "saf"
        field.textDidChange()
        XCTAssertTrue(field.placeholderLayer.isHidden)
        XCTAssertFalse(field.closeLayer.isHidden)
        XCTAssertEqual(field.closeLayer.opacity, 0.3)
        field.setShowsTextField(false)
        XCTAssertTrue(field.textField.isHidden)
        XCTAssertFalse(field.textLayer.isHidden, "While the page zooms, a layer draws the typed text")
        XCTAssertEqual(field.textLayer.string as? String, "saf")
        field.reset()
        XCTAssertTrue(field.textLayer.isHidden)
        XCTAssertFalse(field.isActive)
        XCTAssertFalse(field.placeholderLayer.isHidden)
    }

    /// With Liquid Glass the field draws no background image: its background layer is a capsule for
    /// the stage's glass, and the placeholder and loupe are white at 0.7. Turning the option off
    /// restores the classic field on the next placement.
    @MainActor
    func testGlassFieldIsACapsuleWithBrighterContentAndOffRestoresTheClassicField() {
        let field = ClassicalSearchField()
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let content = CALayer()
        field.placeholder = "Search"
        let frame = CGRect(x: 275, y: 500, width: 250, height: 25)
        field.place(in: content, view: view, frame: frame, scale: 2, rightToLeft: false, usesGlass: true)
        XCTAssertTrue(field.usesGlass)
        XCTAssertEqual(field.backgroundLayer.cornerRadius, 12.5)
        XCTAssertEqual(field.backgroundLayer.cornerCurve, .continuous)
        XCTAssertNil(field.backgroundLayer.contents, "The glass is the background")
        XCTAssertEqual(field.placeholderLayer.foregroundColor?.alpha ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertNotNil(field.loupeLayer.contents)

        field.place(in: content, view: view, frame: frame, scale: 2, rightToLeft: false, usesGlass: false)
        XCTAssertFalse(field.usesGlass)
        XCTAssertEqual(field.backgroundLayer.cornerRadius, 0)
        XCTAssertNotNil(field.backgroundLayer.contents)
        XCTAssertEqual(field.placeholderLayer.foregroundColor?.alpha ?? 0, 0.36, accuracy: 0.0001)
    }

    /// The field's own editor reports every change to composed text to the field it edits.
    @MainActor
    func testTheFieldEditorReportsComposedTextChangesToItsField() throws {
        let textField = ClassicalSearchTextField(frame: .zero)
        let cell = try XCTUnwrap(textField.cell as? ClassicalSearchTextFieldCell)
        let editor = try XCTUnwrap(cell.fieldEditor(for: textField) as? ClassicalSearchFieldEditor)
        XCTAssertTrue(editor.field === textField)
        var reports = 0
        textField.onMarkedTextChange = { reports += 1 }
        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(reports, 1)
        editor.unmarkText()
        XCTAssertGreaterThan(reports, 1, "Ending the composition is reported too")
    }
}
