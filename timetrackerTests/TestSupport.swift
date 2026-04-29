import Foundation
import SwiftData
import Testing
@testable import timetracker

@MainActor
func makeTestContext() throws -> ModelContext {
    let schema = TimeTrackerModelRegistry.currentSchema
    let configuration = ModelConfiguration(
        "TimeTrackerTests",
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
