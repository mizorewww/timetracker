import Foundation
import Testing

@Suite(.serialized)
struct CountdownSettingsContractTests {
    @Test
    func countdownTitleFeedbackIsLocalizedInEverySupportedAppLanguage() throws {
        let keys = [
            "settings.countdown.title.hint",
            "settings.countdown.title.save",
            "settings.countdown.title.saveHint",
            "settings.countdown.title.error.empty",
            "settings.countdown.title.error.tooLong",
            "settings.countdown.title.error.controlCharacters",
            "settings.countdown.title.error.saveFailed"
        ]

        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let stringsURL = try projectRootURL().appending(
                path: "timetracker/\(locale).lproj/Localizable.strings"
            )
            let strings = try #require(NSDictionary(contentsOf: stringsURL) as? [String: String])
            for key in keys {
                #expect(strings[key]?.isEmpty == false, "Missing \(key) in \(locale)")
            }
        }
    }

    @Test
    func countdownEmptyStateDescribesTheCurrentTodayExperience() throws {
        let expectedCopy = [
            "en": "No countdown events yet. Add an event to see it on Today.",
            "zh-Hans": "还没有倒计时事件。添加事件后会显示在“今日”中。",
            "zh-Hant": "還沒有倒數事件。加入事件後會顯示在「今日」中。",
        ]

        for (locale, expected) in expectedCopy {
            let stringsURL = try projectRootURL().appending(
                path: "timetracker/\(locale).lproj/Localizable.strings"
            )
            let strings = try #require(NSDictionary(contentsOf: stringsURL) as? [String: String])
            #expect(strings["settings.countdown.empty"] == expected)
        }
    }

}
