import Foundation
import SwiftData

extension timetrackerApp {
    /// Opens the first store that works: demo, then CloudKit (when enabled),
    /// then the same file without CloudKit, then an in-memory emergency store
    /// that blocks writes. A failure never deletes the on-disk store.
    static func makeModelContainer() -> ModelContainer {
        #if DEBUG
        if AppRuntimeEnvironment.isUITesting {
            do {
                return try makeUITestModelContainer()
            } catch {
                fatalError("Could not create UI test ModelContainer: \(error)")
            }
        }
        #endif
        if AppRuntimeEnvironment.isUnitTestHost() {
            do {
                return try makeUnitTestHostModelContainer()
            } catch {
                preconditionFailure("Could not create unit-test host ModelContainer: \(error)")
            }
        }

        let storeURL = AppCloudSync.persistentStoreURL

        #if DEBUG
        if AppDemoDataConfiguration.usesLocalDemoStore {
            AppCloudSync.recordMode(AppCloudSync.modeDemoData)
            return openOrEmergency(
                ModelConfiguration("TimeTrackerDemo", schema: schema, url: AppDemoDataConfiguration.persistentStoreURL, cloudKitDatabase: .none)
            )
        }
        #endif

        let localConfiguration = ModelConfiguration("TimeTracker", schema: schema, url: storeURL, cloudKitDatabase: .none)
        guard AppCloudSync.isEnabled else {
            AppCloudSync.recordMode(AppCloudSync.modeLocal)
            return openOrEmergency(localConfiguration)
        }

        do {
            let container = try open(
                ModelConfiguration(
                    "TimeTracker",
                    schema: schema,
                    url: storeURL,
                    cloudKitDatabase: .private(AppCloudSync.containerIdentifier)
                )
            )
            AppCloudSync.recordMode(AppCloudSync.modeICloud)
            return container
        } catch {
            AppCloudSync.recordLocalFallback(error: error)
            return openOrEmergency(localConfiguration)
        }
    }

    static var schema: Schema {
        TimeTrackerModelRegistry.currentSchema
    }

    private static func open(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func openOrEmergency(_ configuration: ModelConfiguration) -> ModelContainer {
        do {
            return try open(configuration)
        } catch {
            AppCloudSync.recordEmergencyInMemoryFallback(error: error)
            do {
                return try open(
                    ModelConfiguration("TimeTrackerEmergency", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                )
            } catch {
                preconditionFailure("Could not create emergency in-memory ModelContainer: \(error)")
            }
        }
    }
}
