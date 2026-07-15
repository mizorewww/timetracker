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
    func focusLocalizationKeysExistInEveryMainAppLocale() throws {
        let root = try projectRootURL()
        let requiredKeys = [
            "pomodoro.setup.title",
            "pomodoro.setup.subtitle",
            "pomodoro.focusDuration.accessibility"
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
}
