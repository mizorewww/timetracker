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
        #expect(layout.contains("GeometryReader"))
        #expect(layout.contains("if layout.usesTwoColumnContent"))
        #expect(layout.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(layout.contains("frame(width: layout.contentWidth)"))
        #expect(layout.contains(".contentMargins("))
        #expect(layout.contains("for: .scrollContent"))
        #expect(controls.contains("pomodoro.startFocus"))
        #expect(controls.contains("pomodoro.longBreak"))
        #expect(controls.contains("DurationFormatter.spoken(plan.focusSeconds)"))
        #expect(controls.components(separatedBy: ".buttonStyle(.borderedProminent)").count - 1 == 1)

        let primaryAction = try #require(controls.range(of: "Button(action: startPomodoro)"))
        let planDetails = try #require(controls.range(of: "PomodoroPlanDetails(plan: plan)"))
        #expect(primaryAction.lowerBound < planDetails.lowerBound)
    }

    @Test
    func sectionIdentifiersDoNotOverrideInteractiveDescendants() throws {
        let setup = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupViews.swift"
        )
        let ledger = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroLedgerViews.swift"
        )

        #expect(setup.contains(".accessibilityElement(children: .combine)"))
        #expect(setup.contains(".appCard(padding: 24)\n            .accessibilityIdentifier") == false)
        #expect(ledger.contains(".appCard(padding: 0)\n        .accessibilityIdentifier") == false)
    }

    @Test
    func setupTimerReflowsWithoutShrinkingTaskIdentity() throws {
        let timer = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroTimerFace.swift"
        )
        let selection = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupSelectionViews.swift"
        )

        #expect(timer.contains(".minimumScaleFactor(") == false)
        #expect(timer.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(timer.contains("spokenLabel"))
        #expect(timer.contains("spokenValue"))
        #expect(selection.contains("Text(value)"))
        #expect(selection.contains(".lineLimit(2)"))
        #expect(selection.contains(".minimumScaleFactor(") == false)
        #expect(selection.contains(".multilineTextAlignment(.leading)"))
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
    func stopConfirmationCannotTargetAReplacementPhase() throws {
        let page = try sourceText("timetracker/Features/Pomodoro/PomodoroViews.swift")

        #expect(page.contains("stopConfirmationPhase = PomodoroPhaseToken(run: run)"))
        #expect(page.contains("store.cancelActivePomodoro(phase: stopConfirmationPhase)"))
        #expect(page.contains(".onChange(of: store.activePomodoroRun?.clientMutationID)"))
        #expect(page.contains("mutationID != stopConfirmationPhase?.mutationID"))
        #expect(page.contains("stopConfirmationRunID") == false)
    }

    @Test
    func setupTaskChoiceIsLocalToTheFocusPage() throws {
        let page = try sourceText("timetracker/Features/Pomodoro/PomodoroViews.swift")
        let selection = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupSelectionViews.swift"
        )
        let picker = try sourceText(
            "timetracker/SharedUI/Components/TaskHierarchyPickerSheet.swift"
        )
        let sharedPicker = try [
            "timetracker/SharedUI/Components/TaskHierarchyPicker.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerBehavior.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerPresentation.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let projection = try sourceText(
            "timetracker/SharedUI/Components/TaskHierarchyProjection.swift"
        )
        let controls = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroFocusSetupControls.swift"
        )
        let router = try sourceText("timetracker/App/AppPresentationRouter.swift")

        #expect(page.contains("@State private var focusTaskID"))
        #expect(page.contains("presentationRouter.presentPomodoroTaskPicker("))
        #expect(selection.contains("Button(action: onChooseTask)"))
        #expect(selection.contains("Picker(selection: $focusTaskID)") == false)
        #expect(selection.contains("$store.selectedTaskID") == false)
        #expect(picker.contains("TaskHierarchyPicker("))
        #expect(sharedPicker.contains(".searchable("))
        #expect(projection.contains("store.taskSearchResults(matching: query)"))
        #expect(sharedPicker.contains("\"pomodoro.taskPicker\""))
        #expect(sharedPicker.contains("context.accessibilityIdentifier"))
        #expect(router.contains("case singleTaskPicker(SingleTaskPickerPresentation)"))
        #expect(router.contains("context: .pomodoro"))
        #expect(controls.contains("store.startPomodoro(\n            taskID: focusTaskID"))
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
