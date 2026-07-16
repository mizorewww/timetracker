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
        #expect(routineSource.contains("SettingsDestructiveActionLabel") == false)
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

        #expect(recoverySource.contains("summary: pendingConflict.localSummary"))
        #expect(recoverySource.contains("summary: pendingConflict.cloudSummary"))
        #expect(recoverySource.contains("settings.syncRecovery.replaceCloud"))
        #expect(recoverySource.contains("settings.syncRecovery.replaceDevice"))
        #expect(recoverySource.contains("tint: .green") == false)
        #expect(recoverySource.contains("tint: .cyan") == false)
        #expect(confirmationSource.contains("dialog.forceUpload.confirm"))
        #expect(confirmationSource.contains("dialog.forceDownload.confirm"))
        #expect(confirmationSource.contains("forceUploadLocalData()"))
        #expect(actionsSource.contains("store.resolveSyncConflict(.uploadLocal)"))
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
        }
    }
}
