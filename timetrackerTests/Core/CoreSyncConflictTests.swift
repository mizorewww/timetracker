import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSyncConflictTests {
    @Test @MainActor
    func cloudImportAfterLocalSnapshotPromptsAndUploadRestoresLocalData() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Local plan", parentID: nil, deviceID: "test")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)

            task.title = "Cloud plan"
            task.updatedAt = Date().addingTimeInterval(60)
            try context.save()

            let prompt = try #require(try service.handleCloudImport(context: context))
            #expect(prompt.localSummary.isEmpty == false)
            #expect(prompt.cloudSummary.isEmpty == false)

            try service.resolve(.uploadLocal, context: context)

            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            #expect(tasks.map(\.title) == ["Local plan"])
            #expect(service.prompt() == nil)
        }
    }

    @Test @MainActor
    func cloudImportConflictCanAcceptCloudData() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Local plan", parentID: nil, deviceID: "test")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)

            task.title = "Cloud plan"
            task.updatedAt = Date().addingTimeInterval(60)
            try context.save()

            _ = try #require(try service.handleCloudImport(context: context))
            try service.resolve(.downloadCloud, context: context)

            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            #expect(tasks.map(\.title) == ["Cloud plan"])
            #expect(service.prompt() == nil)
        }
    }

    @Test @MainActor
    func simulatedTwoDeviceConflictCanKeepLocalDeviceData() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Shared base", parentID: nil, deviceID: "device-a")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)
            try service.markCloudExportAccepted(context: context)

            task.title = "Mac local edit"
            task.deviceID = "device-a"
            task.updatedAt = Date().addingTimeInterval(60)
            task.clientMutationID = UUID()
            try context.save()
            try service.recordLocalMutation(context: context)

            task.title = "iPhone remote edit"
            task.deviceID = "device-b"
            task.updatedAt = Date().addingTimeInterval(120)
            task.clientMutationID = UUID()
            try context.save()

            let prompt = try #require(try service.handleCloudImport(context: context))
            #expect(prompt.localSummary.isEmpty == false)
            #expect(prompt.cloudSummary.isEmpty == false)

            try service.resolve(.uploadLocal, context: context)

            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            #expect(tasks.map(\.title) == ["Mac local edit"])
            #expect(service.prompt() == nil)
        }
    }

    @Test @MainActor
    func forceUploadLocalDataMarksCurrentRowsAsNewLocalChanges() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Local plan", parentID: nil, deviceID: "test")
            context.insert(task)
            try context.save()
            let originalMutationID = task.clientMutationID

            let service = SyncConflictService(stateURL: temporaryStateURL())
            let result = try service.forceUploadLocalData(context: context)

            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            #expect(result == .appliedImmediately)
            #expect(tasks.map(\.title) == ["Local plan"])
            #expect(tasks.first?.deviceID == DeviceIdentity.current)
            #expect(tasks.first?.clientMutationID != originalMutationID)
        }
    }

    @Test @MainActor
    func forceUploadDeduplicatesDirtyCloudRowsBeforeExportingLocalWinner() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let id = UUID()
            let older = TaskNode(title: "Older duplicate", parentID: nil, deviceID: "cloud-a")
            older.id = id
            older.createdAt = Date().addingTimeInterval(-120)
            older.updatedAt = Date().addingTimeInterval(-60)
            let newer = TaskNode(title: "Newer duplicate", parentID: nil, deviceID: "cloud-b")
            newer.id = id
            newer.createdAt = Date().addingTimeInterval(-30)
            newer.updatedAt = Date()
            context.insert(older)
            context.insert(newer)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.forceUploadLocalData(context: context) == .appliedImmediately)

            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            let visibleDuplicates = tasks.filter { $0.id == id && $0.deletedAt == nil }
            #expect(visibleDuplicates.map(\.title) == ["Newer duplicate"])
            #expect(tasks.filter { $0.id == id && $0.deletedAt != nil }.count == 1)
        }
    }

    @Test @MainActor
    func forceUploadLocalDataQueuesWhenCloudStorageIsNotActive() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let context = try makeTestContext()
            let task = TaskNode(title: "Fallback local plan", parentID: nil, deviceID: "test")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            let result = try service.forceUploadLocalData(context: context)

            #expect(result == .queuedForNextLaunch)
            #expect(service.prompt() == nil)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.enabledKey))
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
        }
    }

    @Test @MainActor
    func forceUploadPrefersCurrentVisibleDataOverStaleConflictSnapshot() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let stateURL = temporaryStateURL()
            try writeStaleEmptyConflictState(to: stateURL)

            let context = try makeTestContext()
            let task = TaskNode(title: "Current visible plan", parentID: nil, deviceID: "test")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: stateURL)
            #expect(try service.forceUploadLocalData(context: context) == .queuedForNextLaunch)

            let visibleTitles = try context.fetch(FetchDescriptor<TaskNode>())
                .filter { $0.deletedAt == nil }
                .map(\.title)
            #expect(visibleTitles == ["Current visible plan"])

            try withSyncMode(AppCloudSync.modeICloud) {
                let restartContext = try makeTestContext()
                let cloudTask = TaskNode(title: "Cloud plan", parentID: nil, deviceID: "cloud")
                restartContext.insert(cloudTask)
                try restartContext.save()

                #expect(try service.bootstrap(context: restartContext) == nil)
                let restoredTitles = try restartContext.fetch(FetchDescriptor<TaskNode>())
                    .filter { $0.deletedAt == nil }
                    .map(\.title)
                #expect(restoredTitles == ["Current visible plan"])
            }
        }
    }

    @Test @MainActor
    func queuedForceUploadAppliesWhenCloudStorageReturns() throws {
        let stateURL = temporaryStateURL()
        let context = try makeTestContext()
        let task = TaskNode(title: "Queued local plan", parentID: nil, deviceID: "test")
        context.insert(task)
        try context.save()

        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let service = SyncConflictService(stateURL: stateURL)
            let result = try service.forceUploadLocalData(context: context)
            #expect(result == .queuedForNextLaunch)
        }

        task.title = "Cloud plan"
        try context.save()

        try withSyncMode(AppCloudSync.modeICloud) {
            let service = SyncConflictService(stateURL: stateURL)
            #expect(try service.bootstrap(context: context) == nil)
            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            #expect(tasks.map(\.title) == ["Queued local plan"])
        }
    }

    @Test @MainActor
    func forceDownloadQueuesStoreResetWhenCloudStorageIsNotActive() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let context = try makeTestContext()
            let service = SyncConflictService(stateURL: temporaryStateURL())

            #expect(try service.acceptCurrentCloudData(context: context) == .queuedForNextLaunch)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))

            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
        }
    }

    @Test @MainActor
    func forceDownloadFromDemoModeDisablesDemoStoreForRestart() throws {
        try withSyncMode(AppCloudSync.modeDemoData) {
            let previousDemoOverride = UserDefaults.standard.object(forKey: AppDemoDataConfiguration.overrideKey)
            let previousDemoDisabled = UserDefaults.standard.object(forKey: SeedData.automaticDemoSeedingDisabledKey)
            UserDefaults.standard.set(AutomaticDemoDataMode.seedIfEmpty.rawValue, forKey: AppDemoDataConfiguration.overrideKey)
            UserDefaults.standard.set(false, forKey: SeedData.automaticDemoSeedingDisabledKey)
            defer {
                if let previousDemoOverride {
                    UserDefaults.standard.set(previousDemoOverride, forKey: AppDemoDataConfiguration.overrideKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: AppDemoDataConfiguration.overrideKey)
                }
                if let previousDemoDisabled {
                    UserDefaults.standard.set(previousDemoDisabled, forKey: SeedData.automaticDemoSeedingDisabledKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: SeedData.automaticDemoSeedingDisabledKey)
                }
            }

            let context = try makeTestContext()
            let service = SyncConflictService(stateURL: temporaryStateURL())

            #expect(try service.acceptCurrentCloudData(context: context) == .queuedForNextLaunch)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))
            #expect(AppDemoDataConfiguration.currentMode == .off)
            #expect(AppDemoDataConfiguration.usesLocalDemoStore == false)
            #expect(SeedData.isAutomaticDemoSeedingDisabled)
        }
    }

    private func temporaryStateURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeTrackerSyncConflictTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        return url
    }

    private func writeStaleEmptyConflictState(to stateURL: URL) throws {
        let snapshotJSON = emptySnapshotJSON()
        let stateJSON = """
        {
          "localSnapshot": \(snapshotJSON),
          "localFingerprint": "stale-empty-local",
          "pendingConflictID": "\(UUID().uuidString)",
          "pendingDetectedAt": \(Date().timeIntervalSinceReferenceDate),
          "pendingCloudSnapshot": \(snapshotJSON)
        }
        """
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(stateJSON.utf8).write(to: stateURL)
    }

    private func emptySnapshotJSON() -> String {
        """
        {
          "tasks": [],
          "taskCategories": [],
          "taskCategoryAssignments": [],
          "sessions": [],
          "segments": [],
          "pomodoroRuns": [],
          "countdownEvents": [],
          "syncedPreferences": [],
          "checklistItems": [],
          "checklistItemVisuals": [],
          "inboxItems": [],
          "inboxSuggestions": []
        }
        """
    }

    private func withCloudSyncMode(_ body: () throws -> Void) throws {
        try withSyncMode(AppCloudSync.modeICloud, body)
    }

    private func withSyncMode(_ mode: String, _ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.string(forKey: AppCloudSync.modeKey)
        let previousEnabled = defaults.object(forKey: AppCloudSync.enabledKey)
        let previousUploadReset = defaults.object(forKey: AppCloudSync.pendingCloudUploadResetKey)
        let previousDownloadReset = defaults.object(forKey: AppCloudSync.pendingCloudDownloadResetKey)
        defaults.set(mode, forKey: AppCloudSync.modeKey)
        defer {
            if let previousMode {
                defaults.set(previousMode, forKey: AppCloudSync.modeKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.modeKey)
            }
            if let previousEnabled {
                defaults.set(previousEnabled, forKey: AppCloudSync.enabledKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.enabledKey)
            }
            if let previousUploadReset {
                defaults.set(previousUploadReset, forKey: AppCloudSync.pendingCloudUploadResetKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            }
            if let previousDownloadReset {
                defaults.set(previousDownloadReset, forKey: AppCloudSync.pendingCloudDownloadResetKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
            }
        }
        try body()
    }
}
