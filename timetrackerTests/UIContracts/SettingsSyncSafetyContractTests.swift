import Foundation
import Testing

@Suite(.serialized)
struct SettingsSyncSafetyContractTests {
    @Test
    func routineSyncAndDestructiveRecoveryHaveSeparateSections() throws {
        let routineSource = try sourceText(
            "timetracker/Features/Settings/SyncSettingsSection.swift"
        )
        let recoverySource = try sourceText(
            "timetracker/Features/Settings/SyncRecoverySettingsSection.swift"
        )
        let compositionSource = try sourceText(
            "timetracker/Features/Settings/SettingsCategorySections.swift"
        )

        #expect(routineSource.contains("onForceUploadLocal") == false)
        #expect(routineSource.contains("onForceDownloadCloud") == false)
        #expect(routineSource.contains("onForceSync") == false)
        #expect(routineSource.contains("settings.forceSync") == false)
        #expect(routineSource.contains("SettingsDestructiveActionLabel") == false)
        #expect(routineSource.contains("operationMessage") == false)
        #expect(recoverySource.contains("settings.syncRecovery.operationMessage"))
        #expect(recoverySource.contains("struct SyncRecoverySettingsSection"))
        #expect(
            recoverySource.components(separatedBy: "Button(role: .destructive").count == 3
        )
        #expect(
            compositionSource.contains(
                "SyncSettingsSection(\n" +
                    "                cloudSyncEnabled: cloudSyncEnabledBinding"
            )
        )
        #expect(
            compositionSource.contains(
                "SyncRecoverySettingsSection(\n" +
                    "                pendingConflict: store.pendingSyncConflict"
            )
        )
    }

    @Test
    func accountCheckDoesNotPretendToForceCloudKitSync() throws {
        let routineSource = try sourceText(
            "timetracker/Features/Settings/SyncSettingsSection.swift"
        )
        let actionsSource = try sourceText(
            "timetracker/Features/Settings/SettingsViewActions.swift"
        )
        let viewSource = try sourceText(
            "timetracker/Features/Settings/SettingsViews.swift"
        )
        let lifecycleSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+Lifecycle.swift"
        )

        #expect(routineSource.contains("settings.checkSync"))
        #expect(actionsSource.contains("await store.refreshCloudAccountStatus()"))
        #expect(actionsSource.contains("syncOperationMessage = nil"))
        #expect(lifecycleSource.contains("forceCloudSyncRefresh") == false)
        #expect(lifecycleSource.contains("sync.refreshSummary") == false)
        #expect(viewSource.contains("alert.sync.title") == false)
        #expect(viewSource.contains("syncCheckPresented") == false)

        let localeFiles = [
            "timetracker/en.lproj/Localizable.strings",
            "timetracker/zh-Hans.lproj/Localizable.strings",
            "timetracker/zh-Hant.lproj/Localizable.strings"
        ]
        for file in localeFiles {
            let source = try sourceText(file)
            #expect(source.contains("\"settings.checkSync\""))
            #expect(source.contains("CloudKit"))
            #expect(source.contains("\"settings.forceSync\"") == false)
            #expect(source.contains("\"sync.refreshSummary\"") == false)
            #expect(source.contains("\"alert.sync.title\"") == false)
        }
    }

    @Test
    func conflictRecoveryShowsBothCopiesBeforeDirectionalActions() throws {
        let recoverySource = try sourceText(
            "timetracker/Features/Settings/SyncRecoverySettingsSection.swift"
        )
        let confirmationSource = try sourceText(
            "timetracker/Features/Settings/SettingsDestructiveConfirmation.swift"
        )
        let actionsSource = try sourceText(
            "timetracker/Features/Settings/SettingsViewActions.swift"
        )
        let lifecycleSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+Lifecycle.swift"
        )

        #expect(recoverySource.contains("summary: pendingConflict.localSummary"))
        #expect(recoverySource.contains("summary: pendingConflict.cloudSummary"))
        #expect(recoverySource.contains("settings.syncRecovery.replaceCloud"))
        #expect(recoverySource.contains("settings.syncRecovery.replaceDevice"))
        #expect(recoverySource.contains("tint: .green") == false)
        #expect(recoverySource.contains("tint: .cyan") == false)
        #expect(confirmationSource.contains("dialog.forceUpload.confirm"))
        #expect(confirmationSource.contains("dialog.forceDownload.confirm"))
        #expect(confirmationSource.contains("forceUploadLocalData(expectedConflictID: expectedConflictID)"))
        #expect(confirmationSource.contains("case replaceCloud(expectedConflictID: UUID?)"))
        #expect(actionsSource.contains("expectedConflictID: expectedConflictID"))
        #expect(actionsSource.contains("resolution: .uploadLocal"))
        #expect(lifecycleSource.contains(") throws -> SyncConflictResolutionResult"))
        #expect(lifecycleSource.contains("forceUploadLocalDataToCloud") == false)
        #expect(lifecycleSource.contains("func acceptCurrentCloudData()") == false)
        #expect(lifecycleSource.contains("return .failed") == false)
        #expect(actionsSource.contains("sync.conflict.error.changed"))
        #expect(actionsSource.contains("context: .syncRecovery"))
        #expect(actionsSource.contains("sync.forceUpload.conflictResolved"))
        #expect(confirmationSource.contains("Label(AppStrings.localized(\"settings.forceUploadICloud\")") == false)
        #expect(confirmationSource.contains("Label(AppStrings.localized(\"settings.forceDownloadICloud\")") == false)
    }

    @Test
    func recoveryCopyExistsInEveryAppLocale() throws {
        let localeFiles = [
            "timetracker/en.lproj/Localizable.strings",
            "timetracker/zh-Hans.lproj/Localizable.strings",
            "timetracker/zh-Hant.lproj/Localizable.strings"
        ]

        for file in localeFiles {
            let source = try sourceText(file)
            #expect(source.contains("\"settings.syncRecovery.title\""), "Missing recovery title in \(file)")
            #expect(source.contains("\"settings.syncRecovery.replaceCloud\""), "Missing upload direction in \(file)")
            #expect(source.contains("\"settings.syncRecovery.replaceDevice\""), "Missing download direction in \(file)")
            #expect(source.contains("\"dialog.forceUpload.confirm\""), "Missing upload confirmation in \(file)")
            #expect(source.contains("\"dialog.forceDownload.confirm\""), "Missing download confirmation in \(file)")
            #expect(source.contains("\"sync.forceUpload.conflictResolved\""), "Missing upload result in \(file)")
            #expect(source.contains("\"sync.recovery.deferred.conflictingRequests\""), "Missing conflicting recovery copy in \(file)")
            #expect(source.contains("\"sync.conflict.error.recoveryInProgress\""), "Missing active recovery copy in \(file)")
        }
    }

    @Test
    func databaseOptimizationFailureStaysInTheCurrentSettingsScene() throws {
        let maintenanceSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+MaintenanceCommands.swift"
        )
        let confirmationSource = try sourceText(
            "timetracker/Features/Settings/SettingsDestructiveConfirmation.swift"
        )

        #expect(maintenanceSource.contains("func optimizeDatabase() throws -> Int"))
        #expect(maintenanceSource.contains("try performThrowingMutation"))
        #expect(maintenanceSource.contains("removedCount == 0 ? [] : [.fullSync]"))
        #expect(confirmationSource.contains("let removedCount = try store.optimizeDatabase()"))
        #expect(confirmationSource.contains("dialog.optimize.failed"))
        #expect(confirmationSource.contains("context: .databaseMaintenance"))
        #expect(confirmationSource.contains("databaseOptimizationMessage") == false)

        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let strings = try sourceText("timetracker/\(locale).lproj/Localizable.strings")
            #expect(strings.contains("\"dialog.optimize.failed\""))
        }
    }

    @Test
    func cloudActivityIsRecordedOnlyAfterConflictProcessingAndFinalRefresh() throws {
        let observerSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+SyncObservers.swift"
        )
        let feedbackSource = try sourceText(
            "timetracker/Models/SyncFeedbackModels.swift"
        )

        let conflictUpdate = try #require(
            observerSource.range(of: "try updateConflictState(after: batch)")
        )
        let readModelRefresh = try #require(
            observerSource.range(of: "let plan = refreshPlanner.plan(after: [.remoteImportCompleted])")
        )
        let activityRecording = try #require(
            observerSource.range(of: "recordSyncActivity(for: activityReason)")
        )
        #expect(conflictUpdate.lowerBound < readModelRefresh.lowerBound)
        #expect(readModelRefresh.lowerBound < activityRecording.lowerBound)
        #expect(observerSource.contains("pendingSyncConflict = try syncConflictService.handleCloudImport("))
        let importHandling = try #require(
            observerSource.range(of: "pendingSyncConflict = try syncConflictService.handleCloudImport(")
        )
        let exportAcknowledgement = try #require(
            observerSource.range(of: "try syncConflictService.markCloudExportFinished(")
        )
        #expect(importHandling.lowerBound < exportAcknowledgement.lowerBound)
        #expect(
            observerSource.contains(
                "processingFailureMessage: processingFailure.localizedDescription"
            )
        )
        #expect(observerSource.contains("event.error?.localizedDescription"))
        #expect(observerSource.contains("errorMessage =") == false)
        #expect(observerSource.contains("lastSyncRefreshAt") == false)
        #expect(feedbackSource.contains("case let .failed(message)"))
        #expect(feedbackSource.contains("(0...120).contains(now.timeIntervalSince(activity.completedAt))"))
    }

    @Test
    func cloudRecoveryWaitsForTheJournaledInitialImport() throws {
        let factorySource = try sourceText("timetracker/App/AppModelContainerFactory.swift")
        let bufferSource = try sourceText(
            "timetracker/Services/SystemIntegration/CloudReconciliationImportBuffer.swift"
        )
        let configurationSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+Configuration.swift"
        )
        let observerSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+SyncObservers.swift"
        )
        let refreshModelSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+SyncRefreshModels.swift"
        )
        let contentSource = try sourceText("timetracker/App/ContentView.swift")
        let settingsSceneSource = try sourceText("timetracker/App/SettingsSceneView.swift")
        let recoveryServiceSource = try sourceText(
            "timetracker/Services/SystemIntegration/SyncConflictService+Recovery.swift"
        )
        let cloudImportSource = try sourceText(
            "timetracker/Services/SystemIntegration/SyncConflictService+CloudImport.swift"
        )
        let recoveryEventSource = try sourceText(
            "timetracker/Services/SystemIntegration/SyncConflictService+CloudRecoveryEvents.swift"
        )
        let conflictStateSource = try sourceText(
            "timetracker/Services/SystemIntegration/SyncConflictState.swift"
        )

        let bufferStart = try #require(factorySource.range(of: "startIfNeeded()"))
        let cloudContainer = try #require(
            factorySource.range(of: "configurations: [cloudConfiguration]", options: .backwards)
        )
        let recoveryBranch = try #require(
            configurationSource.range(of: "if writeAuthorization.usesApplicationState && AppCloudSync.isCloudRecoveryPending")
        )
        let preferenceMigration = try #require(
            configurationSource.range(of: "SyncedPreferenceService.migrateSensitivePreferences")
        )

        #expect(bufferStart.lowerBound < cloudContainer.lowerBound)
        #expect(bufferSource.contains("event.type == .import"))
        #expect(bufferSource.contains("event.endDate != nil"))
        #expect(bufferSource.contains("event.succeeded"))
        #expect(bufferSource.contains("try recordReceipt(receipt)"))
        #expect(observerSource.contains("CloudRecoveryImportBuffer.shared.stopAndDrain()"))
        #expect(observerSource.contains("recordCloudRecoveryContainerEvent(event)"))
        #expect(observerSource.contains("batch.hasSuccessfulCloudImport"))
        #expect(refreshModelSource.contains("var hasSuccessfulCloudImport: Bool"))
        #expect(cloudImportSource.contains("cloudRecoveryImportIsReady(in: state)"))
        #expect(recoveryEventSource.contains("event.storeIdentifier"))
        #expect(recoveryEventSource.contains("event.succeeded"))
        #expect(conflictStateSource.contains("receipt.startedAt >= startedAt"))
        #expect(conflictStateSource.contains("storeIdentifier == receipt.storeIdentifier"))
        #expect(conflictStateSource.contains("receipt.startedAt >= setupCompletedAt"))
        #expect(recoveryBranch.lowerBound < preferenceMigration.lowerBound)
        #expect(configurationSource.contains("configureCloudRecovery(context: context)"))
        let recoveryConfiguration = try #require(
            configurationSource.slice(
                from: "private func configureCloudRecovery(context: ModelContext)",
                to: "/// Attaches persistence repositories"
            )
        )
        #expect(recoveryConfiguration.contains("refreshCoordinator.refreshReadModels("))
        #expect(recoveryConfiguration.contains("refreshCloudAccountStatus") == false)
        #expect(recoveryConfiguration.contains("try refresh()") == false)
        #expect(contentSource.contains("store.effectivePersistenceWriteSafety"))
        #expect(settingsSceneSource.contains("store.effectivePersistenceWriteSafety"))

        let downloadIntent = try #require(
            recoveryServiceSource.range(of: "AppCloudSync.requestCloudDownloadReset()")
        )
        let stateLoad = try #require(
            recoveryServiceSource.range(of: "var state = try loadState()", range: downloadIntent.lowerBound..<recoveryServiceSource.endIndex)
        )
        #expect(downloadIntent.lowerBound < stateLoad.lowerBound)
    }
}
