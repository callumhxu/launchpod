import Carbon
import XCTest

/// Uses an enabled keyboard layout for XCTest's physical Command-comma event and restores the user's input source.
enum KeyboardInputSourceSupport {
    @MainActor
    static func prepareCommaShortcut(for testCase: XCTestCase) throws {
        let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let originalID = try XCTUnwrap(sourceID(original))
        testCase.addTeardownBlock { @MainActor in
            let status = TISSelectInputSource(original)
            XCTAssertEqual(status, noErr, "Restore the original keyboard input source")
            XCTAssertEqual(sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue()), originalID)
        }

        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as? [TISInputSource] ?? []
        let layouts = sources.filter { source in
            booleanProperty(kTISPropertyInputSourceIsEnabled, of: source)
                && booleanProperty(kTISPropertyInputSourceIsSelectCapable, of: source)
                && booleanProperty(kTISPropertyInputSourceIsASCIICapable, of: source)
                && TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil
        }
        guard let layout = layouts.first(where: { sourceID($0) == "com.apple.keylayout.ABC" }) ?? layouts.first else {
            throw XCTSkip("No enabled ASCII keyboard layout is available for Command-comma")
        }
        let status = TISSelectInputSource(layout)
        guard status == noErr,
              sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue()) == sourceID(layout) else {
            XCTFail("Could not select an ASCII keyboard layout for Command-comma (status \(status))")
            throw SetupError.layoutUnavailable
        }
    }

    private static func sourceID(_ source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }

    private static func booleanProperty(_ key: CFString, of source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }

    private enum SetupError: Error { case layoutUnavailable }
}
