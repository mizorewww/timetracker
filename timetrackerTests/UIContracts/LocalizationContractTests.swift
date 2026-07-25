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
            projectRoot.appending(path: "SharedLiveActivity"),
        ]
        let swiftFiles = try sourceRoots.flatMap { sourceRoot -> [URL] in
            let enumerator = try #require(FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil))
            return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
        let chinesePattern = try NSRegularExpression(pattern: "\\p{Han}")

        for file in swiftFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(source.startIndex ..< source.endIndex, in: source)
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
        #expect(english["task.action.unarchive"] != nil)
        #expect(english["task.action.unarchive.parentFirst"] != nil)
        #expect(english["task.archived.trackingUnavailable"] != nil)
        #expect(english["task.delete.confirm.title"] == nil)
        #expect(english["task.delete.confirm.message"] == nil)
        #expect(english["task.deleted"] == nil)
        #expect(english["task.deleted.path"] == nil)
        #expect(english["task.unavailable"] == "Unavailable Task")
        #expect(english["task.unavailable.path"] == "History / Unavailable Task")
        #expect(english["settings.category.archivedTasks.title"] != nil)
        #expect(english["settings.archivedTasks.footer"] != nil)
    }

    @Test
    func taskLifecycleCopyUsesArchiveUnarchiveAndUnavailableSemantics() throws {
        let root = try projectRootURL()
        let expected: [String: [String: String]] = [
            "en": [
                "menu.task": "Task",
                "menu.archiveSelectedTask": "Archive Selected Task",
                "settings.category.archivedTasks.subtitle": "View and unarchive tasks",
                "task.unavailable": "Unavailable Task",
                "task.unavailable.path": "History / Unavailable Task",
                "task.parent.unavailableLocked": "An unavailable task cannot be moved.",
            ],
            "zh-Hans": [
                "menu.task": "任务",
                "menu.archiveSelectedTask": "归档所选任务",
                "settings.category.archivedTasks.subtitle": "查看并取消归档任务",
                "task.unavailable": "不可用任务",
                "task.unavailable.path": "历史账本 / 不可用任务",
                "task.parent.unavailableLocked": "不可用任务无法移动。",
            ],
            "zh-Hant": [
                "menu.task": "任務",
                "menu.archiveSelectedTask": "封存所選任務",
                "settings.category.archivedTasks.subtitle": "查看並取消封存任務",
                "task.unavailable": "不可用任務",
                "task.unavailable.path": "歷史帳本 / 不可用任務",
                "task.parent.unavailableLocked": "不可用任務無法移動。",
            ],
        ]

        for (locale, expectedValues) in expected {
            let path = root.appending(
                path: "timetracker/\(locale).lproj/Localizable.strings"
            ).path
            let strings = try #require(
                NSDictionary(contentsOfFile: path) as? [String: String]
            )
            for (key, value) in expectedValues {
                #expect(strings[key] == value, "Unexpected \(locale) value for \(key)")
            }
            #expect(strings["task.deleted"] == nil)
            #expect(strings["task.deleted.path"] == nil)
            #expect(strings["task.parent.deletedLocked"] == nil)
        }
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
