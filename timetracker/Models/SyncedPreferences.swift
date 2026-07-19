import Foundation

enum AppPreferenceKey: String, CaseIterable {
    case preferredColorScheme = "PreferredColorScheme"
    case pomodoroDefaultMode = "PomodoroDefaultMode"
    case defaultFocusMinutes = "DefaultFocusMinutes"
    case defaultBreakMinutes = "DefaultBreakMinutes"
    case defaultPomodoroRounds = "DefaultPomodoroRounds"
    case pomodoroPlans = "PomodoroPlans"
    case allowParallelTimers = "AllowParallelTimers"
    case showGrossAndWallTogether = "ShowGrossAndWallTogether"
    case quickStartTaskIDs = "QuickStartTaskIDs"
    case llmEndpoint = "LLMEndpoint"
    case llmSelectedModel = "LLMSelectedModel"
    case llmAvailableModelIDs = "LLMAvailableModelIDs"
    case llmTaskPlanInstructions = "LLMTaskPlanInstructions"
}

enum AppLocalPreferenceKey {
    static let llmAutomaticSuggestionsEnabled = "LLMAutomaticSuggestionsEnabled"
    static let appleHealthTimelineEnabled = "AppleHealthTimelineEnabled"
    static let appleHealthTaskCatalogClearRecoveryTaskIDs =
        "AppleHealthTaskCatalogClearRecoveryIDs"
}

struct AppPreferences: Equatable {
    var preferredColorScheme = "system"
    var pomodoroDefaultMode = PomodoroPreset.classic.rawValue
    var defaultFocusMinutes = 25
    var defaultBreakMinutes = 5
    var defaultPomodoroRounds = 1
    var pomodoroPlans = PomodoroPlan.defaultPlans
    var allowParallelTimers = true
    var showGrossAndWallTogether = true
    var cloudSyncEnabled = AppCloudSync.isEnabled
    var quickStartTaskIDs: [UUID] = []
    var llmEndpoint = "https://api.openai.com/v1"
    var llmAPIKey = ""
    var llmSelectedModel = ""
    var llmAvailableModelIDs: [String] = []
    var llmTaskPlanInstructions = LLMTaskPlanPrompt.defaultInstructions
    var llmAutomaticSuggestionsEnabled = false

    static var defaults: AppPreferences { AppPreferences() }

    init() {}

    init(syncedPreferences: [SyncedPreference]) {
        self = .defaults
        for preference in SyncedPreferenceService.latestByKey(syncedPreferences).values {
            apply(preference)
        }
        normalizeRelatedValues()
    }

    mutating func apply(_ preference: SyncedPreference) {
        guard let key = AppPreferenceKey(rawValue: preference.key), preference.deletedAt == nil else { return }
        switch key {
        case .preferredColorScheme:
            preferredColorScheme = AppPreferenceValueSanitizer.preferredColorScheme(
                PreferenceJSON.decode(String.self, from: preference.valueJSON, default: preferredColorScheme)
            )
        case .pomodoroDefaultMode:
            pomodoroDefaultMode = AppPreferenceValueSanitizer.pomodoroMode(
                PreferenceJSON.decode(String.self, from: preference.valueJSON, default: pomodoroDefaultMode)
            )
        case .defaultFocusMinutes:
            defaultFocusMinutes = PreferenceJSON.decode(Int.self, from: preference.valueJSON, default: defaultFocusMinutes).clamped(to: 1...480)
        case .defaultBreakMinutes:
            defaultBreakMinutes = PreferenceJSON.decode(Int.self, from: preference.valueJSON, default: defaultBreakMinutes).clamped(to: 1...480)
        case .defaultPomodoroRounds:
            defaultPomodoroRounds = PreferenceJSON.decode(Int.self, from: preference.valueJSON, default: defaultPomodoroRounds).clamped(to: 1...24)
        case .pomodoroPlans:
            pomodoroPlans = AppPreferenceValueSanitizer.pomodoroPlans(
                PreferenceJSON.decode([PomodoroPlan].self, from: preference.valueJSON, default: pomodoroPlans)
            )
        case .allowParallelTimers:
            allowParallelTimers = PreferenceJSON.decode(Bool.self, from: preference.valueJSON, default: allowParallelTimers)
        case .showGrossAndWallTogether:
            showGrossAndWallTogether = PreferenceJSON.decode(Bool.self, from: preference.valueJSON, default: showGrossAndWallTogether)
        case .quickStartTaskIDs:
            let strings = PreferenceJSON.decode([String].self, from: preference.valueJSON, default: [])
            quickStartTaskIDs = AppPreferenceValueSanitizer.quickStartTaskIDs(
                strings.compactMap(UUID.init(uuidString:))
            )
        case .llmEndpoint:
            llmEndpoint = AppPreferenceValueSanitizer.llmEndpoint(
                PreferenceJSON.decode(String.self, from: preference.valueJSON, default: llmEndpoint)
            )
        case .llmSelectedModel:
            llmSelectedModel = AppPreferenceValueSanitizer.llmModelID(
                PreferenceJSON.decode(String.self, from: preference.valueJSON, default: llmSelectedModel)
            )
        case .llmAvailableModelIDs:
            llmAvailableModelIDs = AppPreferenceValueSanitizer.llmModelIDs(
                PreferenceJSON.decode([String].self, from: preference.valueJSON, default: [])
            )
        case .llmTaskPlanInstructions:
            let storedValue = PreferenceJSON.decode(
                String.self,
                from: preference.valueJSON,
                default: LLMTaskPlanPrompt.defaultInstructions
            )
            llmTaskPlanInstructions = (try? AppPreferenceValueSanitizer.llmTaskPlanInstructions(
                storedValue
            )) ?? LLMTaskPlanPrompt.defaultInstructions
        }
    }

    private mutating func normalizeRelatedValues() {
        if !llmSelectedModel.isEmpty, !llmAvailableModelIDs.contains(llmSelectedModel) {
            llmSelectedModel = ""
        }
    }

    func valueJSON(for key: AppPreferenceKey) -> String {
        switch key {
        case .preferredColorScheme:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.preferredColorScheme(preferredColorScheme))
        case .pomodoroDefaultMode:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroMode(pomodoroDefaultMode))
        case .defaultFocusMinutes:
            return PreferenceJSON.encode(defaultFocusMinutes)
        case .defaultBreakMinutes:
            return PreferenceJSON.encode(defaultBreakMinutes)
        case .defaultPomodoroRounds:
            return PreferenceJSON.encode(defaultPomodoroRounds)
        case .pomodoroPlans:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroPlans(pomodoroPlans))
        case .allowParallelTimers:
            return PreferenceJSON.encode(allowParallelTimers)
        case .showGrossAndWallTogether:
            return PreferenceJSON.encode(showGrossAndWallTogether)
        case .quickStartTaskIDs:
            return PreferenceJSON.encode(
                AppPreferenceValueSanitizer.quickStartTaskIDs(quickStartTaskIDs).map(\.uuidString)
            )
        case .llmEndpoint:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.llmEndpoint(llmEndpoint))
        case .llmSelectedModel:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.llmModelID(llmSelectedModel))
        case .llmAvailableModelIDs:
            return PreferenceJSON.encode(AppPreferenceValueSanitizer.llmModelIDs(llmAvailableModelIDs))
        case .llmTaskPlanInstructions:
            let instructions = (try? AppPreferenceValueSanitizer.llmTaskPlanInstructions(
                llmTaskPlanInstructions
            )) ?? LLMTaskPlanPrompt.defaultInstructions
            return PreferenceJSON.encode(instructions)
        }
    }
}

enum SyncedPreferenceService {
    static let migrationKey = "SyncedPreferencesMigratedToSwiftDataV1"
    static let legacyLLMAPIKey = "LLMAPIKey"
    static let legacyCloudSyncEnabledKey = AppCloudSync.enabledKey

    static func isSensitiveKey(_ key: String) -> Bool {
        key == legacyLLMAPIKey
    }

    static func isDeviceLocalKey(_ key: String) -> Bool {
        key == legacyCloudSyncEnabledKey
    }

    static func shouldSyncKey(_ key: String) -> Bool {
        !isSensitiveKey(key) && !isDeviceLocalKey(key)
    }

    static func latestByKey(_ preferences: [SyncedPreference]) -> [String: SyncedPreference] {
        preferences
            .reduce(into: [String: SyncedPreference]()) { result, preference in
                guard let existing = result[preference.key] else {
                    result[preference.key] = preference
                    return
                }
                if preference.updatedAt > existing.updatedAt ||
                    (preference.updatedAt == existing.updatedAt &&
                        preference.deletedAt != nil && existing.deletedAt == nil) ||
                    (preference.updatedAt == existing.updatedAt &&
                        (preference.deletedAt == nil) == (existing.deletedAt == nil) &&
                        (preference.createdAt > existing.createdAt ||
                            (preference.createdAt == existing.createdAt &&
                                preference.id.uuidString > existing.id.uuidString))) {
                    result[preference.key] = preference
                }
            }
    }

}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
