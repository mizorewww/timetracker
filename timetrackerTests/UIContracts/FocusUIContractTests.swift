import Foundation
import Testing

@Suite(.serialized)
struct FocusUIContractTests {
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
            "pomodoro.remaining.accessibility",
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
