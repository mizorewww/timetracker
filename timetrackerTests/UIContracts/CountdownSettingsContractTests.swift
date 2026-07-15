import Foundation
import Testing

@Suite(.serialized)
struct CountdownSettingsContractTests {
    @Test
    func countdownTitleUsesADeliberateAccessibleDraftCommitFlow() throws {
        let editorSource = try sourceText("timetracker/Features/Settings/CountdownTitleEditor.swift")
        let rowSource = try sourceText("timetracker/Features/Settings/Support/SettingsSupportViews.swift")
        let sectionSource = try sourceText("timetracker/Features/Settings/CountdownSettingsSection.swift")
        let settingsSource = try sourceText("timetracker/Features/Settings/SettingsViews.swift")
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+CountdownCommands.swift")

        #expect(editorSource.contains("text: $draft.text"))
        #expect(editorSource.contains(".onSubmit(commitTitle)"))
        #expect(editorSource.contains(".onChange(of: isTitleFocused)"))
        #expect(editorSource.contains("Button(AppStrings.localized(\"common.save\"), action: commitTitle)"))
        #expect(editorSource.contains("settings.countdown.title.hint"))
        #expect(editorSource.contains("settings.countdown.title.error"))
        #expect(editorSource.contains(".accessibilityLabel(error.localizedMessage)"))
        #expect(editorSource.contains(".accessibilityIdentifier(\"settings.countdown.title.field\")"))
        #expect(editorSource.contains(".accessibilityIdentifier(\"settings.countdown.title.save\")"))
        #expect(rowSource.contains("CountdownTitleEditor("))
        #expect(rowSource.contains("titleBinding") == false)
        #expect(sectionSource.contains("let onChangeTitle: (CountdownEvent, String) -> Bool"))
        #expect(settingsSource.contains("NavigationLink {\n                        settingsForm(for: category)"))
        #expect(settingsSource.contains("NavigationLink(value: category)") == false)
        #expect(settingsSource.contains("settings.category.\\(category.rawValue)"))
        #expect(storeSource.contains("func updateCountdownEvent") && storeSource.contains("-> Bool"))
    }

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
}
