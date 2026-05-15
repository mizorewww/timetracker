import Foundation
import SwiftData

extension timetrackerApp {
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

    static func makeModelContainer() -> ModelContainer {
        let schema = Self.schema
        if CommandLine.arguments.contains("--uitesting") {
            do {
                return try makeUITestModelContainer()
            } catch {
                fatalError("Could not create UI test ModelContainer: \(error)")
            }
        }

        let cloudConfiguration = ModelConfiguration(
            "TimeTracker",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(AppCloudSync.containerIdentifier)
        )
        let localConfiguration = ModelConfiguration(
            "TimeTracker",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        let emergencyConfiguration = ModelConfiguration(
            "TimeTrackerEmergency",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        if AppDemoDataConfiguration.usesLocalDemoStore {
            AppCloudSync.recordDemoDataMode()
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

        guard AppCloudSync.isEnabled else {
            AppCloudSync.recordCloudKitDisabledByUser()
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

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [cloudConfiguration]
            )
            AppCloudSync.recordCloudKitEnabled()
            return container
        } catch {
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

    private static var schema: Schema {
        TimeTrackerModelRegistry.currentSchema
    }

    private static func makeEmergencyModelContainer(
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
            preconditionFailure("Could not create emergency in-memory ModelContainer: \(error)")
        }
    }
}
