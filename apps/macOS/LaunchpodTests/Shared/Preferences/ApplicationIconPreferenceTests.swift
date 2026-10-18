import AppKit
import Foundation
import Testing
@testable import Launchpod

@MainActor
struct ApplicationIconPreferenceTests {
    private final class RecordingApplier: ApplicationIconApplying {
        var applied: [ApplicationIcon] = []
        var error: TestError?
        var onNotify: () -> Void = {}

        func apply(_ icon: ApplicationIcon) throws {
            applied.append(icon)
            if let error { throw error }
        }

        func notifyDockTile() {
            onNotify()
        }
    }

    private enum TestError: Error {
        case unavailable
    }

    @Test
    func missingChoiceAppliesTheDefaultIconAndNotifiesTheDockTile() throws {
        try withDefaults { defaults in
            let applier = RecordingApplier()
            var notificationCount = 0
            applier.onNotify = { notificationCount += 1 }

            let preference = ApplicationIconPreference(defaults: defaults, applier: applier)

            #expect(preference.selection == .colorTiles)
            #expect(applier.applied == [.colorTiles])
            #expect(notificationCount == 1)
        }
    }

    @Test
    func everyChoicePersistsAppliesNotifiesAndRestores() throws {
        try withDefaults { defaults in
            let applier = RecordingApplier()
            var notificationCount = 0
            applier.onNotify = { notificationCount += 1 }
            let preference = ApplicationIconPreference(defaults: defaults, applier: applier)
            let choices = Array(ApplicationIcon.allCases.dropFirst()) + [.colorTiles]

            for (index, icon) in choices.enumerated() {
                preference.select(icon)
                #expect(preference.selection == icon)
                #expect(defaults.string(forKey: ApplicationIconPreference.preferenceKey) == icon.rawValue)
                #expect(applier.applied.last == icon)
                #expect(notificationCount == index + 2)

                let restoredApplier = RecordingApplier()
                let restored = ApplicationIconPreference(defaults: defaults, applier: restoredApplier)
                #expect(restored.selection == icon)
                #expect(restoredApplier.applied == [icon])
            }
        }
    }

    @Test(arguments: ["", "unknown", "Application Icon", "1"])
    func unsupportedStoredIdentifiersRecoverToTheDefaultIcon(invalidValue: String) throws {
        try withDefaults { defaults in
            defaults.set(invalidValue, forKey: ApplicationIconPreference.preferenceKey)
            let applier = RecordingApplier()
            let preference = ApplicationIconPreference(defaults: defaults, applier: applier)

            #expect(preference.selection == .colorTiles)
            #expect(applier.applied == [.colorTiles])
        }
    }

    @Test
    func malformedStoredValueRecoversToTheDefaultIcon() throws {
        try withDefaults { defaults in
            defaults.set(["icon"], forKey: ApplicationIconPreference.preferenceKey)
            let applier = RecordingApplier()
            let preference = ApplicationIconPreference(defaults: defaults, applier: applier)

            #expect(preference.selection == .colorTiles)
            #expect(applier.applied == [.colorTiles])
        }
    }

    @Test
    func unavailableCustomAssetPreservesSelectionAndDefaultsWithoutNotifying() throws {
        try withDefaults { defaults in
            defaults.set(ApplicationIcon.colorGrid.rawValue, forKey: ApplicationIconPreference.preferenceKey)
            var notificationCount = 0
            let applier = SystemApplicationIconApplier(
                loadImage: { iconName in
                    iconName == ApplicationIcon.colorGrid.assetName
                        ? NSImage(size: NSSize(width: 16, height: 16))
                        : nil
                },
                setRunningIcon: { _ in },
                postDockTileChange: { notificationCount += 1 }
            )
            let preference = ApplicationIconPreference(defaults: defaults, applier: applier)

            preference.select(.darkGrid)

            #expect(preference.selection == .colorGrid)
            #expect(defaults.string(forKey: ApplicationIconPreference.preferenceKey) == ApplicationIcon.colorGrid.rawValue)
            #expect(notificationCount == 1)
        }
    }

    @Test
    func successfulSelectionPersistsBeforeNotifyingTheDockTile() throws {
        try withDefaults { defaults in
            let applier = RecordingApplier()
            var preference: ApplicationIconPreference?
            var observedSelection: ApplicationIcon?
            var observedStoredIdentifier: String?
            var notificationCount = 0
            applier.onNotify = {
                notificationCount += 1
                observedSelection = preference?.selection
                observedStoredIdentifier = defaults.string(forKey: ApplicationIconPreference.preferenceKey)
            }
            preference = ApplicationIconPreference(defaults: defaults, applier: applier)

            notificationCount = 0
            preference?.select(.rocket)

            #expect(notificationCount == 1)
            #expect(observedSelection == .rocket)
            #expect(observedStoredIdentifier == ApplicationIcon.rocket.rawValue)
        }
    }

    @Test
    func reselectingTheCurrentChoiceReappliesAndNotifiesWithoutChangingDefaults() throws {
        try withDefaults { defaults in
            defaults.set(ApplicationIcon.rocket.rawValue, forKey: ApplicationIconPreference.preferenceKey)
            let applier = RecordingApplier()
            var notificationCount = 0
            applier.onNotify = { notificationCount += 1 }
            let preference = ApplicationIconPreference(defaults: defaults, applier: applier)
            notificationCount = 0
            let initialApplicationCount = applier.applied.count

            preference.select(preference.selection)

            #expect(applier.applied.count == initialApplicationCount + 1)
            #expect(applier.applied.last == .rocket)
            #expect(defaults.string(forKey: ApplicationIconPreference.preferenceKey) == ApplicationIcon.rocket.rawValue)
            #expect(notificationCount == 1)
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let preferences = try TemporaryPreferences()
        let defaults = preferences.defaults
        defer { #expect(throws: Never.self) { try preferences.cleanup() } }
        try body(defaults)
    }
}
