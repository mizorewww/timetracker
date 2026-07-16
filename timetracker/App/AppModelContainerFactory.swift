import Foundation
import SwiftData

extension timetrackerApp {
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

    static var schema: Schema {
        TimeTrackerModelRegistry.currentSchema
    }
}
