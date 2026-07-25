import Foundation
import SwiftData
import Testing
@testable import timetracker

@MainActor
func makeTestContext() throws -> ModelContext {
    let schema = TimeTrackerModelRegistry.currentSchema
    let configuration = ModelConfiguration(
        "TimeTrackerTests-\(UUID().uuidString)",
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(
        for: schema,
        migrationPlan: TimeTrackerMigrationPlan.self,
        configurations: [configuration]
    )
    return ModelContext(container)
}

@MainActor
func makeTestStore() -> TimeTrackerStore {
    TimeTrackerStore(
        appleHealthDataReader: UnavailableAppleHealthDataReader(),
        appleHealthTimelinePreferenceStore:
        TestAppleHealthTimelinePreferenceStore(),
        writeAuthorization: .isolatedTestHarness
    )
}

@MainActor
func makeTestStore(
    llmCredentialStore: any LLMCredentialStoring
) -> TimeTrackerStore {
    makeTestStore(
        llmCredentialStore: llmCredentialStore,
        appleHealthTimelinePreferenceStore:
        TestAppleHealthTimelinePreferenceStore()
    )
}

@MainActor
func makeTestStore(
    llmCredentialStore: any LLMCredentialStoring,
    appleHealthTimelinePreferenceStore:
    any AppleHealthTimelinePreferenceStoring
) -> TimeTrackerStore {
    TimeTrackerStore(
        llmCredentialStore: llmCredentialStore,
        appleHealthDataReader: UnavailableAppleHealthDataReader(),
        appleHealthTimelinePreferenceStore:
        appleHealthTimelinePreferenceStore,
        writeAuthorization: .isolatedTestHarness
    )
}

@MainActor
func makeTestSystemActionCommandHandler() -> SystemActionCommandHandler {
    SystemActionCommandHandler(writeAuthorization: .isolatedTestHarness)
}

@MainActor
func makeTestWatchCommandProcessor(
    receiptStore: WatchCommandReceiptStore
) -> WatchCommandProcessor {
    WatchCommandProcessor(
        receiptStore: receiptStore,
        writeAuthorization: .isolatedTestHarness
    )
}

@MainActor
func setTestAllowParallelTimers(
    _ isEnabled: Bool,
    context: ModelContext
) throws {
    try PreferenceCommandHandler().set(
        key: .allowParallelTimers,
        valueJSON: PreferenceJSON.encode(isEnabled),
        context: context
    )
}

@MainActor
func makeTestStore(
    llmCredentialStore: any LLMCredentialStoring,
    inboxSuggestionService: LLMInboxSuggestionService
) -> TimeTrackerStore {
    TimeTrackerStore(
        llmCredentialStore: llmCredentialStore,
        inboxSuggestionService: inboxSuggestionService,
        appleHealthDataReader: UnavailableAppleHealthDataReader(),
        appleHealthTimelinePreferenceStore:
        TestAppleHealthTimelinePreferenceStore(),
        writeAuthorization: .isolatedTestHarness
    )
}

@MainActor
func makeTestStore(
    llmCredentialStore: any LLMCredentialStoring,
    inboxSuggestionService: LLMInboxSuggestionService,
    checklistVisualSuggestionService: LLMChecklistVisualSuggestionService
) -> TimeTrackerStore {
    TimeTrackerStore(
        llmCredentialStore: llmCredentialStore,
        inboxSuggestionService: inboxSuggestionService,
        checklistVisualSuggestionService: checklistVisualSuggestionService,
        appleHealthDataReader: UnavailableAppleHealthDataReader(),
        appleHealthTimelinePreferenceStore:
        TestAppleHealthTimelinePreferenceStore(),
        writeAuthorization: .isolatedTestHarness
    )
}

@MainActor
final class TestAppleHealthTimelinePreferenceStore:
    AppleHealthTimelinePreferenceStoring
{
    var isTimelineEnabled: Bool
    var taskCatalogClearRecoveryTaskIDs: Set<UUID> = []

    init(isTimelineEnabled: Bool = false) {
        self.isTimelineEnabled = isTimelineEnabled
    }
}

func projectRootURL() throws -> URL {
    var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while current.path != "/" {
        if FileManager.default.fileExists(atPath: current.appending(path: "timetracker.xcodeproj").path) {
            return current
        }
        current.deleteLastPathComponent()
    }

    struct ProjectRootError: Error {}
    throw ProjectRootError()
}

func sourceText(_ relativePath: String) throws -> String {
    try String(contentsOf: projectRootURL().appending(path: relativePath), encoding: .utf8)
}

extension String {
    func slice(from start: String, to end: String) -> String? {
        guard let startRange = range(of: start),
              let endRange = range(of: end, range: startRange.upperBound ..< endIndex)
        else {
            return nil
        }
        return String(self[startRange.lowerBound ..< endRange.lowerBound])
    }
}
