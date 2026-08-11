import Foundation
import SwiftData

extension timetrackerApp {
    static func makeModelContainer() -> ModelContainer {
        let schema = Self.schema
        #if DEBUG
        if CommandLine.arguments.contains("--uitesting") {
            do {
                return try makeUITestModelContainer()
            } catch {
                fatalError("Could not create UI test ModelContainer: \(error)")
            }
        }
        #endif
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

        AppCloudSync.prepareInterruptedCloudDownloadRecovery()
        let recoveryGate: AppCloudSync.CloudRecoveryGate
        do {
            recoveryGate = try performPendingCloudRecoveryResetAfterProtectingLocalFallback(
                schema: schema,
                localConfiguration: localConfiguration,
                storeURL: storeURL
            )
        } catch {
            // The existing local store is still the only fully current copy.
            // Never delete it when its protected recovery branch could not be
            // brought up to date first.
            return makeLocalFallbackModelContainer(
                schema: schema,
                localConfiguration: localConfiguration,
                emergencyConfiguration: emergencyConfiguration,
                error: error
            )
        }

        let completedRecovery: AppCloudSync.CompletedCloudRecovery
        switch recoveryGate {
        case let .completed(recovery):
            completedRecovery = recovery
        case let .deferred(reason):
            return makeLocalFallbackModelContainer(
                schema: schema,
                localConfiguration: localConfiguration,
                emergencyConfiguration: emergencyConfiguration,
                error: reason
            )
        case let .failed(failure):
            return makeLocalFallbackModelContainer(
                schema: schema,
                localConfiguration: localConfiguration,
                emergencyConfiguration: emergencyConfiguration,
                error: failure
            )
        }

        if AppDefaults.shared.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) ||
            AppCloudSync.isCloudImportRecoveryActive ||
            completedRecovery.reset == .download
        {
            CloudRecoveryImportBuffer.shared.startIfNeeded()
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
            CloudRecoveryImportBuffer.shared.stopAndDiscard()
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
