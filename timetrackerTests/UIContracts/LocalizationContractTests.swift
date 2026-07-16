import Foundation
import Testing

@Suite(.serialized)
struct LocalizationContractTests {
    @Test
    func localizationFilesExposeTheSameKeys() throws {
        let locales = ["en", "zh-Hans", "zh-Hant"]
        let keySets = try locales.map { locale -> Set<String> in
            let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: "\(locale).lproj"))
            let dictionary = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            #expect(dictionary.isEmpty == false)
            return Set(dictionary.keys)
        }

        let reference = try #require(keySets.first)
        for keys in keySets.dropFirst() {
            #expect(keys == reference)
        }

        for locale in locales {
            let path = try #require(Bundle.main.path(
                forResource: "Localizable",
                ofType: "strings",
                inDirectory: "\(locale).lproj"
            ))
            let values = try #require(
                NSDictionary(contentsOfFile: path) as? [String: String]
            ).values
            #expect(values.contains { $0.localizedCaseInsensitiveContains("soft delete") } == false)
            #expect(values.contains { $0.contains("软删除") || $0.contains("軟刪除") } == false)
        }
    }

    @Test
    func liveActivityExtensionLocalizationFilesExposeTheSameKeys() throws {
        let projectRoot = try projectRootURL()
        let locales = ["en", "zh-Hans", "zh-Hant"]
        let keySets = try locales.map { locale -> Set<String> in
            let path = projectRoot.appending(path: "timetrackerLiveActivityExtension/\(locale).lproj/Localizable.strings").path
            let dictionary = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            #expect(dictionary.isEmpty == false)
            return Set(dictionary.keys)
        }

        let reference = try #require(keySets.first)
        for keys in keySets.dropFirst() {
            #expect(keys == reference)
        }
    }

    @Test
    func widgetExtensionLocalizationFilesExposeTheSameKeys() throws {
        let projectRoot = try projectRootURL()
        let locales = ["en", "zh-Hans", "zh-Hant"]
        let keySets = try locales.map { locale -> Set<String> in
            let path = projectRoot.appending(path: "timetrackerWidgetExtension/\(locale).lproj/Localizable.strings").path
            let dictionary = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            #expect(dictionary.isEmpty == false)
            return Set(dictionary.keys)
        }

        let reference = try #require(keySets.first)
        for keys in keySets.dropFirst() {
            #expect(keys == reference)
        }
    }

    @Test
    func watchAppLocalizationFilesExposeTheSameKeys() throws {
        let projectRoot = try projectRootURL()
        let locales = ["en", "zh-Hans", "zh-Hant"]
        let keySets = try locales.map { locale -> Set<String> in
            let path = projectRoot.appending(path: "timetrackerWatchApp/\(locale).lproj/Localizable.strings").path
            let dictionary = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            #expect(dictionary.isEmpty == false)
            return Set(dictionary.keys)
        }

        let reference = try #require(keySets.first)
        for keys in keySets.dropFirst() {
            #expect(keys == reference)
        }
    }

    @Test
    func swiftSourcesDoNotContainHardCodedChineseText() throws {
        let projectRoot = try projectRootURL()
        let sourceRoots = [
            projectRoot.appending(path: "timetracker"),
            projectRoot.appending(path: "timetrackerLiveActivityExtension"),
            projectRoot.appending(path: "timetrackerWidgetExtension"),
            projectRoot.appending(path: "timetrackerWatchApp"),
            projectRoot.appending(path: "SharedLiveActivity")
        ]
        let swiftFiles = try sourceRoots.flatMap { sourceRoot -> [URL] in
            let enumerator = try #require(FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil))
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
        let chinesePattern = try NSRegularExpression(pattern: "\\p{Han}")

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            #expect(chinesePattern.firstMatch(in: source, range: range) == nil, "Move user-facing Chinese text into Localizable.strings: \(file.lastPathComponent)")
        }
    }

    @Test
    func destructiveResetWarningNamesLocalCredentialsAndConsent() throws {
        let projectRoot = try projectRootURL()
        let englishPath = projectRoot.appending(path: "timetracker/en.lproj/Localizable.strings").path
        let english = try #require(NSDictionary(contentsOfFile: englishPath) as? [String: String])
        let warning = try #require(english["dialog.resetData.message"])

        #expect(warning.contains("local LLM API key"))
        #expect(warning.contains("automatic-suggestion consent"))
        #expect(english["task.action.archive.stopFirst"] != nil)
        #expect(english["task.archived.trackingUnavailable"] != nil)
    }

    @Test
    func taskPersistenceLengthErrorsExposeExactByteCountsInEveryLocale() throws {
        let root = try projectRootURL()
        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let path = root.appending(path: "timetracker/\(locale).lproj/Localizable.strings").path
            let strings = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
            let format = try #require(strings["persistence.error.tooLongFormat"])

            #expect(format.contains("%@"), "Missing field placeholder for \(locale)")
            #expect(
                format.components(separatedBy: "%lld").count == 3,
                "Expected current and maximum byte placeholders for \(locale)"
            )
            #expect(try #require(strings["persistence.error.requiredFormat"]).isEmpty == false)
            #expect(try #require(strings["persistence.error.controlCharacterFormat"]).isEmpty == false)
        }
    }
}
