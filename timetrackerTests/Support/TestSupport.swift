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
        writeAuthorization: .isolatedTestHarness
    )
}

@MainActor
func makeTestSystemActionCommandHandler() -> SystemActionCommandHandler {
    SystemActionCommandHandler(writeAuthorization: .isolatedTestHarness)
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
