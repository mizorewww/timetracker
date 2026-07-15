import Foundation
import Testing

@Suite(.serialized)
struct FocusUIContractTests {
    @Test
    func setupUsesOnePrimaryActionAndAnAdaptiveHistoryColumn() throws {
        let setup = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupViews.swift"
        )
        let controls = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroFocusSetupControls.swift"
        )
        let layout = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroPageLayout.swift"
        )

        #expect(setup.contains("PomodoroPageLayout"))
        #expect(setup.contains("PomodoroLedgerCard"))
        #expect(setup.contains("pomodoro.setup.title"))
        #expect(layout.contains("ViewThatFits(in: .horizontal)"))
        #expect(layout.contains("frame(minWidth: 440, maxWidth: 580)"))
        #expect(controls.contains("pomodoro.startFocus"))
        #expect(controls.contains("pomodoro.longBreak"))
        #expect(controls.contains("DurationFormatter.spoken(plan.focusSeconds)"))
        #expect(controls.components(separatedBy: ".buttonStyle(.borderedProminent)").count - 1 == 1)
    }

    @Test
    func setupTimerReflowsWithoutShrinkingTaskIdentity() throws {
        let timer = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroTimerFace.swift"
        )

        #expect(timer.contains(".minimumScaleFactor(") == false)
        #expect(timer.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(timer.contains("spokenLabel"))
        #expect(timer.contains("spokenValue"))
    }

    @Test
    func activePageLimitsPerSecondInvalidationToTheCountdown() throws {
        let page = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroActiveViews.swift"
        )
        let countdown = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroActiveCountdownView.swift"
        )
        let schedule = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroCountdownSchedule.swift"
        )

        #expect(page.contains("TimelineView") == false)
        #expect(page.contains("PomodoroPageLayout"))
        #expect(countdown.contains("TimelineView(PomodoroCountdownSchedule"))
        #expect(countdown.contains("pomodoro.skipBreak"))
        #expect(countdown.contains(".disabled(canResumeFocus == false)"))
        #expect(countdown.contains("pomodoro.resume.unavailable"))
        #expect(countdown.contains(".accessibilityHidden(true)"))
        #expect(schedule.contains("guard currentDate < endDate else { return nil }"))
        #expect(schedule.contains("mode == .lowFrequency ? 60 : 1"))
    }

    @Test
    func stopConfirmationCannotTargetAReplacementRun() throws {
        let page = try sourceText("timetracker/Features/Pomodoro/PomodoroViews.swift")

        #expect(page.contains("stopConfirmationRunID = run.id"))
        #expect(page.contains("store.activePomodoroRun?.id == stopConfirmationRunID"))
        #expect(page.contains(".onChange(of: store.activePomodoroRun?.id)"))
    }

    @Test
    func focusLocalizationKeysExistInEveryMainAppLocale() throws {
        let root = try projectRootURL()
        let requiredKeys = [
            "pomodoro.setup.title",
            "pomodoro.setup.subtitle",
            "pomodoro.focusDuration.accessibility",
            "pomodoro.skipBreak",
            "pomodoro.skipBreak.hint",
            "pomodoro.startNextFocus.hint",
            "pomodoro.resume.unavailable",
            "pomodoro.roundsCompleted",
            "pomodoro.phaseTask.accessibility",
            "pomodoro.remaining.accessibility"
        ]

        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let path = root.appending(
                path: "timetracker/\(locale).lproj/Localizable.strings"
            ).path
            let strings = try #require(
                NSDictionary(contentsOfFile: path) as? [String: String]
            )
            for key in requiredKeys {
                #expect(try #require(strings[key]).isEmpty == false)
            }
        }
    }

    @Test
    func focusNavigationUsesOneCrossPlatformTitleWithoutRenamingLedgerSources() throws {
        let strings = try sourceText("timetracker/Shared/AppStrings.swift")
        let destinations = try sourceText("timetracker/Stores/Facade/TimeTrackerStore.swift")
        let phoneRoot = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let focusPage = try sourceText("timetracker/Features/Pomodoro/PomodoroViews.swift")

        #expect(strings.contains("static let focus = localized(\"nav.focus\")"))
        #expect(strings.contains("static let pomodoro = localized(\"nav.pomodoro\")"))
        #expect(destinations.contains("case .pomodoro: return AppStrings.focus"))
        #expect(phoneRoot.contains("Label(AppStrings.focus, systemImage: \"timer\")"))
        #expect(focusPage.contains(".navigationTitle(AppStrings.focus)"))
    }
}
