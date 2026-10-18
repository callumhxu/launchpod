import Testing
@testable import Launchpod

@MainActor
struct OnboardingDemoStateTests {
    @Test
    func movingAnAppBeforeAnotherPreservesEveryAppAndTheOtherAppsOrder() {
        var state = OnboardingDemoState()

        state.move(.calendar, before: .music)
        #expect(state.apps == [.notes, .calendar, .music, .photos])
        #expect(state.folderApps.isEmpty)
        state.move(.notes, before: .photos)
        #expect(state.apps == [.calendar, .music, .notes, .photos])
        state.move(.music, before: .music)
        #expect(state.apps == [.calendar, .music, .notes, .photos])
    }

    @Test
    func searchingShowsNotesWithoutRemovingOrReorderingTheSampleApps() {
        var state = OnboardingDemoState()
        state.move(.calendar, before: .notes)
        let originalOrder = state.apps

        state.searchForNotes()

        #expect(state.visibleApps == [.notes])
        #expect(state.apps == originalOrder)
        #expect(!state.query.isEmpty)
        #expect(state.folderApps.isEmpty)
    }

    @Test
    func creatingAndOpeningAFolderKeepsItsMembersAndOtherApps() {
        var state = OnboardingDemoState()
        state.openFolder()
        #expect(!state.isFolderOpen)

        state.createFolder()
        #expect(state.folderApps == [.notes, .music])
        #expect(state.apps == [.photos, .calendar])
        state.createFolder()
        #expect(state.folderApps == [.notes, .music])
        #expect(state.apps == [.photos, .calendar])

        state.openFolder()
        #expect(state.isFolderOpen)
        state.closeFolder()
        #expect(!state.isFolderOpen)
        #expect(state.folderApps == [.notes, .music])
        #expect(state.apps == [.photos, .calendar])
    }

    @Test
    func movingAnAppThatIsInsideAFolderDoesNotChangeTheGrid() {
        var state = OnboardingDemoState()
        state.createFolder()

        state.move(.notes, before: .calendar)
        state.move(.calendar, before: .music)

        #expect(state.apps == [.photos, .calendar])
        #expect(state.folderApps == [.notes, .music])
    }

    @Test
    func resetRestoresTheWholeIllustrationAndDoesNotAffectAnotherDemo() {
        var state = OnboardingDemoState()
        var otherDemo = OnboardingDemoState()
        otherDemo.move(.calendar, before: .notes)
        state.move(.photos, before: .notes)
        state.searchForNotes()
        state.createFolder()
        state.openFolder()

        state.reset()

        #expect(state.apps == [.notes, .music, .photos, .calendar])
        #expect(state.visibleApps == state.apps)
        #expect(state.folderApps.isEmpty)
        #expect(!state.isFolderOpen)
        #expect(state.query.isEmpty)
        #expect(otherDemo.apps == [.calendar, .notes, .music, .photos])
    }
}
