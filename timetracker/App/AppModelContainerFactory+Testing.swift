import Foundation
import SwiftData

extension timetrackerApp {
    static func makeUnitTestHostModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TimeTrackerUnitTestHost",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeUITestModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TimeTrackerUITests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        AppCloudSync.recordUITesting()
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
