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

    static func makeModelContainer() -> ModelContainer {
        let schema = Self.schema
        if CommandLine.arguments.contains("--uitesting") {
            do {
                return try makeUITestModelContainer()
            } catch {
                fatalError("Could not create UI test ModelContainer: \(error)")
            }
        }
        if isUnitTestHost() {
            do {
                return try makeUnitTestHostModelContainer()
            } catch {
                preconditionFailure("Could not create unit-test host ModelContainer: \(error)")
            }
        }

        let storeURL = AppCloudSync.persistentStoreURL
        let cloudConfiguration = ModelConfiguration(
            "TimeTracker",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .private(AppCloudSync.containerIdentifier)
        )
        let localConfiguration = ModelConfiguration(
            "TimeTracker",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let demoConfiguration = ModelConfiguration(
            "TimeTrackerDemo",
            schema: schema,
            url: AppDemoDataConfiguration.persistentStoreURL,
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
                    configurations: [demoConfiguration]
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

        let recoveryGate = AppCloudSync.performPendingCloudRecoveryResetIfNeeded(
            canResetUpload: SyncConflictService.hasDefaultPendingForcedUploadBackup()
        )

        let completedRecovery: AppCloudSync.CompletedCloudRecovery
        switch recoveryGate {
        case .completed(let recovery):
            completedRecovery = recovery
        case .deferred(let reason):
            return makeLocalFallbackModelContainer(
                schema: schema,
                localConfiguration: localConfiguration,
                emergencyConfiguration: emergencyConfiguration,
                error: reason
            )
        case .failed(let failure):
            return makeLocalFallbackModelContainer(
                schema: schema,
                localConfiguration: localConfiguration,
                emergencyConfiguration: emergencyConfiguration,
                error: failure
            )
        }

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [cloudConfiguration]
            )
            AppCloudSync.recordCloudKitEnabled(after: completedRecovery)
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

    static func isUnitTestHost(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
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

    private static func makeLocalFallbackModelContainer(
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
