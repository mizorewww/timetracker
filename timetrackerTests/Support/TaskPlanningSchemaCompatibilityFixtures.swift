import Foundation
import SwiftData
@testable import timetracker

@MainActor
struct LegacyV12TaskPlanningStoreFixture {
    let fixture: LegacyStoreFixture<UUID>

    var storeURL: URL {
        fixture.storeURL
    }

    var taskID: UUID {
        fixture.seed
    }

    static func create() throws -> LegacyV12TaskPlanningStoreFixture {
        try LegacyV12TaskPlanningStoreFixture(
            fixture: LegacyStoreFixture.create(
                name: "LegacyV12TaskPlanning",
                schema: TimeTrackerSchemaV12.self,
                directoryPrefix: "LegacyV12"
            ) { context in
                let task = TaskNode(
                    title: "V12 preserved task",
                    parentID: nil,
                    deviceID: "legacy"
                )
                context.insert(task)
                return task.id
            }
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try fixture.withCurrentContext(body)
    }

    func remove() {
        fixture.remove()
    }
}
