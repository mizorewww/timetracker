import Foundation

nonisolated enum LLMReasoningEffort:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case automatic
    case low
    case medium
    case high
    case max

    var id: Self {
        self
    }
}

nonisolated enum AppPreferenceKey: String, CaseIterable {
    case preferredColorScheme = "PreferredColorScheme"
    case pomodoroPlans = "PomodoroPlans"
    case allowParallelTimers = "AllowParallelTimers"
    case showGrossAndWallTogether = "ShowGrossAndWallTogether"
    case quickStartTaskIDs = "QuickStartTaskIDs"
    case todayHeatmapTaskIDs = "TodayHeatmapTaskIDs"
    case todayHeatmapPeriod = "TodayHeatmapPeriod"
    case llmEndpoint = "LLMEndpoint"
    case llmSelectedModel = "LLMSelectedModel"
    case llmAvailableModelIDs = "LLMAvailableModelIDs"
    case llmReasoningEffort = "LLMReasoningEffort"
    case llmInboxSuggestionInstructions = "LLMInboxSuggestionInstructions"
    case llmChecklistVisualInstructions = "LLMChecklistVisualInstructions"
    case llmTaskPlanInstructions = "LLMTaskPlanInstructions"
}

enum AppLocalPreferenceKey {
    static let llmAutomaticSuggestionsEnabled = "LLMAutomaticSuggestionsEnabled"
    static let macKeyboardShortcutOverrides = "MacKeyboardShortcutOverrides"
}

struct AppPreferences: Equatable {
    var preferredColorScheme = "system"
    var pomodoroPlans = PomodoroPlan.defaultPlans
    var allowParallelTimers = true
    var showGrossAndWallTogether = true
    var cloudSyncEnabled = AppCloudSync.isEnabled
    var quickStartTaskIDs: [UUID] = []
    var todayHeatmapTaskIDs: [UUID] = []
    var todayHeatmapPeriod = ActivityHeatmapPeriod.standard
    var llmEndpoint = "https://api.openai.com/v1"
    var llmAPIKey = ""
    var llmSelectedModel = ""
    var llmAvailableModelIDs: [String] = []
    var llmReasoningEffort = LLMReasoningEffort.automatic
    var llmInboxSuggestionInstructions = LLMPromptKind.inboxRouting.defaultInstructions
    var llmChecklistVisualInstructions = LLMPromptKind.checklistVisual.defaultInstructions
    var llmTaskPlanInstructions = LLMTaskPlanPrompt.defaultInstructions
    var llmAutomaticSuggestionsEnabled = false

    static var defaults: AppPreferences {
        AppPreferences()
    }

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
        case .todayHeatmapTaskIDs:
            let strings = PreferenceJSON.decode([String].self, from: preference.valueJSON, default: [])
            todayHeatmapTaskIDs = AppPreferenceValueSanitizer.todayHeatmapTaskIDs(
                strings.compactMap(UUID.init(uuidString:))
            )
        case .todayHeatmapPeriod:
            todayHeatmapPeriod = AppPreferenceValueSanitizer.todayHeatmapPeriod(
                PreferenceJSON.decode(
                    String.self,
                    from: preference.valueJSON,
                    default: ActivityHeatmapPeriod.standard.rawValue
                )
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
        case .llmReasoningEffort:
            llmReasoningEffort =
                AppPreferenceValueSanitizer.llmReasoningEffort(
                    PreferenceJSON.decode(
                        String.self,
                        from: preference.valueJSON,
                        default: llmReasoningEffort.rawValue
                    )
                )
        case .llmInboxSuggestionInstructions:
            llmInboxSuggestionInstructions = Self.storedInstructions(preference.valueJSON, for: .inboxRouting)
        case .llmChecklistVisualInstructions:
            llmChecklistVisualInstructions = Self.storedInstructions(preference.valueJSON, for: .checklistVisual)
        case .llmTaskPlanInstructions:
            llmTaskPlanInstructions = Self.storedInstructions(preference.valueJSON, for: .taskPlan)
        }
    }

    private mutating func normalizeRelatedValues() {
        if !llmSelectedModel.isEmpty, !llmAvailableModelIDs.contains(llmSelectedModel) {
            llmSelectedModel = ""
        }
    }

    /// Invalid stored instructions fall back to the prompt's defaults.
    private static func storedInstructions(_ valueJSON: String, for kind: LLMPromptKind) -> String {
        let value = PreferenceJSON.decode(String.self, from: valueJSON, default: kind.defaultInstructions)
        return (try? AppPreferenceValueSanitizer.llmPromptInstructions(value, for: kind)) ?? kind.defaultInstructions
    }

    func llmInstructions(for kind: LLMPromptKind) -> String {
        switch kind {
        case .inboxRouting:
            llmInboxSuggestionInstructions
        case .checklistVisual:
            llmChecklistVisualInstructions
        case .taskPlan:
            llmTaskPlanInstructions
        }
    }
}

enum SyncedPreferenceService {
    nonisolated static let legacyLLMAPIKey = "LLMAPIKey"
    nonisolated static let legacyCloudSyncEnabledKey =
        AppCloudSync.enabledKey

    nonisolated static func isSensitiveKey(_ key: String) -> Bool {
        key == legacyLLMAPIKey
    }

    nonisolated static func isDeviceLocalKey(_ key: String) -> Bool {
        key == legacyCloudSyncEnabledKey
    }

    nonisolated static func shouldSyncKey(_ key: String) -> Bool {
        !isSensitiveKey(key) && !isDeviceLocalKey(key)
    }

    nonisolated static func latestByKey(
        _ preferences: [SyncedPreference]
    ) -> [String: SyncedPreference] {
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
                                preference.id > existing.id)))
                {
                    result[preference.key] = preference
                }
            }
    }
}

nonisolated extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
