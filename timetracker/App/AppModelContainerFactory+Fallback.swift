import SwiftData

extension timetrackerApp {
    static func makeEmergencyModelContainer(
        schema: Schema,
        configuration: ModelConfiguration,
        error: Error
    ) -> ModelContainer {
        AppCloudSync.recordEmergencyInMemoryFallback(error: error)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            preconditionFailure(
                "Could not create emergency in-memory ModelContainer: \(error)"
            )
        }
    }

    static func makeLocalFallbackModelContainer(
        schema: Schema,
        localConfiguration: ModelConfiguration,
        emergencyConfiguration: ModelConfiguration,
        error: Error
    ) -> ModelContainer {
        AppCloudSync.recordLocalFallback(error: error)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [localConfiguration]
            )
        } catch {
            return makeEmergencyModelContainer(
                schema: schema,
                configuration: emergencyConfiguration,
                error: error
            )
        }
    }
}
