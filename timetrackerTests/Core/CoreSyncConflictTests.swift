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

            #expect(
                try service.resolveSyncConflict(
                    expectedConflictID: prompt.id,
                    resolution: .uploadLocal,
                    context: context
                ) == .appliedImmediately
            )

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

            let prompt = try #require(try service.handleCloudImport(context: context))
            #expect(
                try service.resolveSyncConflict(
                    expectedConflictID: prompt.id,
                    resolution: .downloadCloud,
                    context: context
                ) == .appliedImmediately
            )

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
            try acknowledgeCurrentCloudExport(service: service, context: context)

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

            #expect(
                try service.resolveSyncConflict(
                    expectedConflictID: prompt.id,
                    resolution: .uploadLocal,
                    context: context
                ) == .appliedImmediately
            )

            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            #expect(tasks.map(\.title) == ["Mac local edit"])
            #expect(service.prompt() == nil)
        }
    }

    @Test @MainActor
    func baselineCloudReplayCannotSilentlyReplaceANewerLocalEdit() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let baseDate = Date(timeIntervalSinceReferenceDate: 1_400_000)
            let task = TaskNode(title: "Shared base", parentID: nil, deviceID: "device-a")
            task.createdAt = baseDate
            task.updatedAt = baseDate
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)
            try acknowledgeCurrentCloudExport(service: service, context: context)

            task.title = "Unexported local edit"
            task.updatedAt = baseDate.addingTimeInterval(60)
            task.clientMutationID = UUID()
            try context.save()
            try service.recordLocalMutation(context: context)

            // Simulate CloudKit replaying the last accepted baseline after the
            // local edit was recorded but before its export completed.
            task.title = "Shared base"
            task.updatedAt = baseDate
            task.clientMutationID = UUID()
            try context.save()

            #expect(try service.handleCloudImport(context: context) == nil)
            let restoredTask = try #require(
                try context.fetch(FetchDescriptor<TaskNode>()).visibleDeduplicatedByID().first
            )
            let state = try service.loadState()
            #expect(restoredTask.title == "Unexported local edit")
            #expect(state.localSnapshot?.tasks.first?.title == "Unexported local edit")
            #expect(state.localFingerprint != state.baseFingerprint)
            #expect((state.localGeneration ?? 0) > (state.baseAcknowledgedGeneration ?? 0))
        }
    }

    @Test @MainActor
    func olderExportCompletionCannotAcknowledgeANewerLocalEdit() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let base = Date(timeIntervalSinceReferenceDate: 1_500_000)
            let task = TaskNode(title: "Shared base", parentID: nil, deviceID: "device-a")
            task.createdAt = base
            task.updatedAt = base
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)
            try acknowledgeCurrentCloudExport(service: service, context: context)

            task.title = "Local edit one"
            task.updatedAt = base.addingTimeInterval(10)
            task.clientMutationID = UUID()
            try context.save()
            try service.recordLocalMutation(context: context)

            let firstExportID = UUID()
            try service.markCloudExportStarted(eventID: firstExportID)

            task.title = "Local edit two"
            task.updatedAt = base.addingTimeInterval(20)
            task.clientMutationID = UUID()
            try context.save()
            try service.recordLocalMutation(context: context)

            // Only "Local edit one" was part of this export event.
            try service.markCloudExportFinished(eventID: firstExportID, succeeded: true)

            task.title = "Remote edit"
            task.deviceID = "device-b"
            task.updatedAt = base.addingTimeInterval(30)
            task.clientMutationID = UUID()
            try context.save()

            let prompt = try #require(try service.handleCloudImport(context: context))
            #expect(
                try service.resolveSyncConflict(
                    expectedConflictID: prompt.id,
                    resolution: .uploadLocal,
                    context: context
                ) == .appliedImmediately
            )
            #expect(try context.fetch(FetchDescriptor<TaskNode>()).visibleDeduplicatedByID().first?.title == "Local edit two")
        }
    }

    @Test @MainActor
    func overlappingExportsCannotMoveTheAcceptedGenerationBackwards() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Base", parentID: nil, deviceID: "device-a")
            context.insert(task)
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)
            try acknowledgeCurrentCloudExport(service: service, context: context)

            task.title = "Generation one"
            task.updatedAt = Date().addingTimeInterval(10)
            try context.save()
            try service.recordLocalMutation(context: context)
            let firstID = UUID()
            try service.markCloudExportStarted(eventID: firstID)

            task.title = "Generation two"
            task.updatedAt = Date().addingTimeInterval(20)
            try context.save()
            try service.recordLocalMutation(context: context)
            let secondID = UUID()
            try service.markCloudExportStarted(eventID: secondID)
            let secondFingerprint = try SyncDataSnapshot.capture(context: context).fingerprint()

            try service.markCloudExportFinished(eventID: secondID, succeeded: true)
            try service.markCloudExportFinished(eventID: firstID, succeeded: true)

            let state = try service.loadState()
            #expect(state.baseFingerprint == secondFingerprint)
            #expect(state.baseAcknowledgedGeneration == state.localGeneration)
        }
    }

    @Test @MainActor
    func failedAndOrphanedExportCheckpointsStayBoundedAndNeverAdvanceBase() throws {
        try withCloudSyncMode {
            let stateURL = temporaryStateURL()
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Bounded state", parentID: nil, deviceID: "device-a"))
            try context.save()
            let service = SyncConflictService(stateURL: stateURL)
            #expect(try service.bootstrap(context: context) == nil)
            let baseBeforeFailure = try service.loadState().baseFingerprint

            let failedID = UUID()
            try service.markCloudExportStarted(eventID: failedID)
            try service.markCloudExportFinished(eventID: failedID, succeeded: false)
            #expect(try service.loadState().baseFingerprint == baseBeforeFailure)
            #expect(try service.loadState().pendingCloudExportCheckpoints?.isEmpty ?? true)

            let start = Date(timeIntervalSinceReferenceDate: 2_000_000)
            for index in 0..<100 {
                try service.markCloudExportStarted(
                    eventID: UUID(),
                    now: start.addingTimeInterval(Double(index))
                )
            }
            let boundedState = try service.loadState()
            #expect((boundedState.pendingCloudExportCheckpoints?.count ?? 0) <= 16)
            #expect(try Data(contentsOf: stateURL).count < 64_000)

            try service.markCloudExportFinished(eventID: UUID(), succeeded: true)
            #expect(try service.loadState().baseFingerprint == baseBeforeFailure)
        }
    }

    @Test @MainActor
    func separateServiceInstancesSerializeTheSameStateFile() async throws {
        let stateURL = temporaryStateURL()
        let firstService = SyncConflictService(stateURL: stateURL)
        let secondService = SyncConflictService(stateURL: stateURL)
        let firstEntered = DispatchSemaphore(value: 0)
        let releaseFirst = DispatchSemaphore(value: 0)
        let secondAttempted = DispatchSemaphore(value: 0)
        let secondEntered = DispatchSemaphore(value: 0)

        let firstTask = Task.detached(priority: .high) {
            try firstService.withExclusiveStateAccess {
                firstEntered.signal()
                releaseFirst.wait()
            }
        }
        defer { releaseFirst.signal() }
        let firstEntryResult = await waitForSemaphore(firstEntered, timeout: .now() + 2)
        try #require(firstEntryResult == .success)

        let secondTask = Task.detached(priority: .high) {
            secondAttempted.signal()
            _ = try secondService.withExclusiveStateAccess {
                secondEntered.signal()
            }
        }
        let secondAttemptResult = await waitForSemaphore(secondAttempted, timeout: .now() + 2)
        try #require(secondAttemptResult == .success)
        let blockedResult = await waitForSemaphore(secondEntered, timeout: .now() + 0.05)
        #expect(blockedResult == .timedOut)

        #if os(macOS)
        let lockedProcess = Process()
        lockedProcess.executableURL = URL(fileURLWithPath: "/usr/bin/lockf")
        lockedProcess.arguments = [
            "-t", "0", try firstService.stateLockURL().path, "/usr/bin/true"
        ]
        lockedProcess.standardError = Pipe()
        try lockedProcess.run()
        lockedProcess.waitUntilExit()
        #expect(lockedProcess.terminationStatus != 0)
        #endif

        releaseFirst.signal()
        try await firstTask.value
        try await secondTask.value
        let releasedResult = await waitForSemaphore(secondEntered, timeout: .now() + 1)
        #expect(releasedResult == .success)

        #if os(macOS)
        let releasedProcess = Process()
        releasedProcess.executableURL = URL(fileURLWithPath: "/usr/bin/lockf")
        releasedProcess.arguments = [
            "-t", "1", try firstService.stateLockURL().path, "/usr/bin/true"
        ]
        releasedProcess.standardError = Pipe()
        try releasedProcess.run()
        releasedProcess.waitUntilExit()
        #expect(releasedProcess.terminationStatus == 0)
        #endif
    }

    @Test @MainActor
    func twoServicesAndContextsPreserveInterleavedDomainsAndExportCheckpoints() throws {
        try withCloudSyncMode {
            let stateURL = temporaryStateURL()
            let firstContext = try makeTestContext()
            let secondContext = try makeTestContext()
            let firstService = SyncConflictService(stateURL: stateURL)
            let secondService = SyncConflictService(stateURL: stateURL)

            let task = TaskNode(title: "Base task", parentID: nil, deviceID: "app")
            firstContext.insert(task)
            try firstContext.save()
            #expect(try firstService.bootstrap(context: firstContext) == nil)
            try acknowledgeCurrentCloudExport(service: firstService, context: firstContext)

            task.title = "App task edit"
            task.updatedAt = Date().addingTimeInterval(10)
            task.clientMutationID = UUID()
            try firstContext.save()
            try firstService.recordLocalMutation(
                context: firstContext,
                events: [.taskChanged(taskID: task.id, affectedAncestorIDs: [])]
            )
            let appExportID = UUID()
            try firstService.markCloudExportStarted(eventID: appExportID)

            let inbox = InboxItem(title: "Shortcut capture", sortOrder: 0, deviceID: "shortcut")
            secondContext.insert(inbox)
            try secondContext.save()
            try secondService.recordLocalMutation(
                context: secondContext,
                events: [.inboxChanged(itemIDs: [inbox.id])]
            )
            let shortcutExportID = UUID()
            try secondService.markCloudExportStarted(eventID: shortcutExportID)

            var state = try firstService.loadState()
            #expect(state.pendingCloudExportCheckpoints?.count == 2)
            #expect(state.localSnapshot?.tasks.map(\.title) == ["App task edit"])
            #expect(state.localSnapshot?.inboxItems.map(\.title) == ["Shortcut capture"])

            try firstService.markCloudExportFinished(eventID: appExportID, succeeded: true)
            state = try secondService.loadState()
            #expect(state.pendingCloudExportCheckpoints?[shortcutExportID.uuidString] != nil)
            #expect((state.baseAcknowledgedGeneration ?? 0) < (state.localGeneration ?? 0))

            task.title = "App task edit after Shortcut"
            task.updatedAt = Date().addingTimeInterval(20)
            task.clientMutationID = UUID()
            try firstContext.save()
            try firstService.recordLocalMutation(
                context: firstContext,
                events: [.taskChanged(taskID: task.id, affectedAncestorIDs: [])]
            )

            state = try secondService.loadState()
            #expect(state.localSnapshot?.tasks.map(\.title) == ["App task edit after Shortcut"])
            #expect(state.localSnapshot?.inboxItems.map(\.title) == ["Shortcut capture"])
            #expect(state.pendingCloudExportCheckpoints?[shortcutExportID.uuidString] != nil)
        }
    }

    @Test @MainActor
    func authoritativeStateSuppressesAnOrphanedForcedUploadMirror() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let stateURL = temporaryStateURL()
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Local winner", parentID: nil, deviceID: "device-a"))
            try context.save()

            let firstService = SyncConflictService(stateURL: stateURL)
            _ = try firstService.forceUploadLocalData(context: context)
            let backupURL = try firstService.pendingForcedUploadSnapshotURL()
            let stagedBackupData = try Data(contentsOf: backupURL)

            _ = try firstService.acceptCurrentCloudData(context: context)
            #expect(FileManager.default.fileExists(atPath: backupURL.path) == false)

            // Simulate termination after the authoritative clear committed but
            // before a stale recovery mirror could be removed.
            try stagedBackupData.write(to: backupURL, options: [.atomic])
            let secondService = SyncConflictService(stateURL: stateURL)
            #expect(try secondService.loadPendingForcedUploadSnapshot() == nil)
            #expect(FileManager.default.fileExists(atPath: backupURL.path) == false)
        }
    }

    @Test @MainActor
    func postConflictEditsAreAppliedToTheSavedLocalBranch() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Shared base", parentID: nil, deviceID: "device-a")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)
            try acknowledgeCurrentCloudExport(service: service, context: context)

            task.title = "Mac local edit"
            task.updatedAt = Date().addingTimeInterval(60)
            try context.save()
            try service.recordLocalMutation(context: context)

            task.title = "iPhone cloud edit"
            task.updatedAt = Date().addingTimeInterval(120)
            try context.save()
            let prompt = try #require(try service.handleCloudImport(context: context))

            let laterTask = TaskNode(title: "Post-conflict task", parentID: nil, deviceID: "device-a")
            context.insert(laterTask)
            try context.save()
            try service.recordLocalMutation(context: context)
            let currentPrompt = try #require(service.prompt())
            #expect(currentPrompt.id != prompt.id)

            #expect(
                try service.resolveSyncConflict(
                    expectedConflictID: currentPrompt.id,
                    resolution: .uploadLocal,
                    context: context
                ) == .appliedImmediately
            )

            let visibleTitles = try context.fetch(FetchDescriptor<TaskNode>())
                .filter { $0.deletedAt == nil }
                .map(\.title)
                .sorted()
            #expect(visibleTitles == ["Mac local edit", "Post-conflict task"])
        }
    }

    @Test @MainActor
    func localMutationSnapshotRefreshesOnlyTheChangedDomain() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let base = Date(timeIntervalSinceReferenceDate: 1_200_000)
            let task = TaskNode(title: "Base task", parentID: nil, deviceID: "device-a")
            task.createdAt = base
            task.updatedAt = base
            let inbox = InboxItem(title: "Base inbox", deviceID: "device-a")
            inbox.createdAt = base
            inbox.updatedAt = base
            context.insert(task)
            context.insert(inbox)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)
            try acknowledgeCurrentCloudExport(service: service, context: context)

            task.title = "Local task edit"
            task.updatedAt = base.addingTimeInterval(10)
            task.clientMutationID = UUID()
            inbox.title = "Unreported inbox edit"
            inbox.updatedAt = base.addingTimeInterval(10)
            inbox.clientMutationID = UUID()
            try context.save()
            try service.recordLocalMutation(
                context: context,
                events: [.taskChanged(taskID: task.id, affectedAncestorIDs: [])]
            )

            task.title = "Cloud task edit"
            task.updatedAt = base.addingTimeInterval(20)
            task.clientMutationID = UUID()
            inbox.title = "Cloud inbox edit"
            inbox.updatedAt = base.addingTimeInterval(20)
            inbox.clientMutationID = UUID()
            try context.save()
            let prompt = try #require(try service.handleCloudImport(context: context))

            #expect(
                try service.resolveSyncConflict(
                    expectedConflictID: prompt.id,
                    resolution: .uploadLocal,
                    context: context
                ) == .appliedImmediately
            )

            let restoredTask = try #require(
                try context.fetch(FetchDescriptor<TaskNode>()).visibleDeduplicatedByID().first
            )
            let restoredInbox = try #require(
                try context.fetch(FetchDescriptor<InboxItem>()).visibleDeduplicatedByID().first
            )
            #expect(restoredTask.title == "Local task edit")
            #expect(restoredInbox.title == "Base inbox")
        }
    }

    @Test @MainActor
    func acceptingCloudRestoresTheExactPromptSnapshotAfterLaterEdits() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Shared base", parentID: nil, deviceID: "device-a")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)
            try acknowledgeCurrentCloudExport(service: service, context: context)

            task.title = "Mac local edit"
            task.updatedAt = Date().addingTimeInterval(60)
            try context.save()
            try service.recordLocalMutation(context: context)

            task.title = "iPhone cloud edit"
            task.updatedAt = Date().addingTimeInterval(120)
            try context.save()
            let prompt = try #require(try service.handleCloudImport(context: context))

            let laterTask = TaskNode(title: "Post-conflict task", parentID: nil, deviceID: "device-a")
            context.insert(laterTask)
            try context.save()
            try service.recordLocalMutation(context: context)
            try acknowledgeCurrentCloudExport(service: service, context: context)
            let currentPrompt = try #require(service.prompt())
            #expect(currentPrompt.id != prompt.id)

            #expect(
                try service.resolveSyncConflict(
                    expectedConflictID: currentPrompt.id,
                    resolution: .downloadCloud,
                    context: context
                ) == .appliedImmediately
            )

            let visibleTitles = try context.fetch(FetchDescriptor<TaskNode>())
                .filter { $0.deletedAt == nil }
                .map(\.title)
            #expect(visibleTitles == ["iPhone cloud edit"])
        }
    }

    @Test @MainActor
    func acceptingCloudIncludesRemoteChangesImportedWhileConflictPromptIsPending() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Shared base", parentID: nil, deviceID: "device-a")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)
            try acknowledgeCurrentCloudExport(service: service, context: context)

            task.title = "Mac local edit"
            task.updatedAt = Date().addingTimeInterval(60)
            try context.save()
            try service.recordLocalMutation(context: context)

            task.title = "iPhone cloud edit"
            task.updatedAt = Date().addingTimeInterval(120)
            try context.save()
            let prompt = try #require(try service.handleCloudImport(context: context))

            let laterRemoteTask = TaskNode(title: "Later remote task", parentID: nil, deviceID: "device-b")
            laterRemoteTask.updatedAt = Date().addingTimeInterval(180)
            context.insert(laterRemoteTask)
            try context.save()
            let currentPrompt = try #require(try service.handleCloudImport(context: context))
            #expect(currentPrompt.id != prompt.id)

            #expect(
                try service.resolveSyncConflict(
                    expectedConflictID: currentPrompt.id,
                    resolution: .downloadCloud,
                    context: context
                ) == .appliedImmediately
            )

            let visibleTitles = try context.fetch(FetchDescriptor<TaskNode>())
                .filter { $0.deletedAt == nil }
                .map(\.title)
            #expect(Set(visibleTitles) == ["iPhone cloud edit", "Later remote task"])
        }
    }

    @Test @MainActor
    func threeWayMergeDeduplicatesLegacySnapshotIdentifiers() {
        let id = UUID()
        let baseDate = Date(timeIntervalSinceReferenceDate: 400_000)
        func record(_ title: String, updatedAt: Date) -> TaskRecord {
            let task = TaskNode(title: title, parentID: nil, deviceID: "legacy")
            task.id = id
            task.createdAt = baseDate
            task.updatedAt = updatedAt
            return TaskRecord(task)
        }

        var localSnapshot = SyncDataSnapshot(tasks: [
            record("Discarded local duplicate", updatedAt: baseDate),
            record("Local branch", updatedAt: baseDate.addingTimeInterval(1))
        ])
        let baselineSnapshot = SyncDataSnapshot(tasks: [
            record("Discarded baseline duplicate", updatedAt: baseDate),
            record("Baseline", updatedAt: baseDate.addingTimeInterval(1))
        ])
        let updatedSnapshot = SyncDataSnapshot(tasks: [
            record("Discarded updated duplicate", updatedAt: baseDate),
            record("Updated branch", updatedAt: baseDate.addingTimeInterval(2))
        ])

        localSnapshot.applyChanges(from: baselineSnapshot, to: updatedSnapshot)

        #expect(localSnapshot.tasks.count == 1)
        #expect(localSnapshot.tasks.first?.title == "Updated branch")
    }

    @Test @MainActor
    func invalidPomodoroSnapshotValuesAreRejectedDuringRestorePreflight() throws {
        let sourceContext = try makeTestContext()
        let run = PomodoroRun(
            taskID: UUID(),
            focus: -120,
            breakSeconds: 0,
            longBreakSeconds: -30,
            targetRounds: 0,
            deviceID: "legacy"
        )
        run.state = .focusing
        run.startedAt = Date(timeIntervalSinceReferenceDate: 500_000)
        run.completedFocusRounds = -4
        sourceContext.insert(run)
        try sourceContext.save()
        let snapshot = try SyncDataSnapshot.capture(context: sourceContext)

        let restoredContext = try makeTestContext()
        #expect(throws: SyncDataSnapshotPreflightError.invalidInteger(
            table: .pomodoroRuns,
            id: run.id,
            field: "focusSecondsPlanned",
            value: -120,
            allowed: "1...28800"
        )) {
            try snapshot.restoreAsLocalWinner(
                context: restoredContext,
                now: Date(timeIntervalSinceReferenceDate: 600_000)
            )
        }
        #expect(try restoredContext.fetch(FetchDescriptor<PomodoroRun>()).isEmpty)
    }

    @Test @MainActor
    func invalidTaskEstimateIsClampedDuringSnapshotRestore() throws {
        let sourceContext = try makeTestContext()
        let task = TaskNode(title: "Legacy estimate", parentID: nil, deviceID: "legacy")
        task.estimatedSeconds = Int.max
        sourceContext.insert(task)
        try sourceContext.save()
        let snapshot = try SyncDataSnapshot.capture(context: sourceContext)

        let restoredContext = try makeTestContext()
        try snapshot.restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 600_000)
        )
        let restoredTask = try #require(
            try restoredContext.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID()
                .first
        )

        #expect(restoredTask.estimatedSeconds == TaskEstimatePolicy.maximumSeconds)
    }

    @Test @MainActor
    func settingsOnlySnapshotIsProtectedAndCanQueueForcedUpload() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let context = try makeTestContext()
            let preference = SyncedPreference(
                key: AppPreferenceKey.llmEndpoint.rawValue,
                valueJSON: PreferenceJSON.encode("https://example.test/v1"),
                deviceID: "device-a"
            )
            context.insert(preference)
            try context.save()

            let snapshot = try SyncDataSnapshot.capture(context: context)
            #expect(snapshot.hasProtectableUserContent)
            #expect(snapshot.hasVisibleUserContent)

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.forceUploadLocalData(context: context) == .queuedForNextLaunch)
            let queuedSnapshot = try #require(try service.loadPendingForcedUploadSnapshot())
            #expect(queuedSnapshot.syncedPreferences.map(\.key) == [AppPreferenceKey.llmEndpoint.rawValue])
        }
    }

    @Test @MainActor
    func deletingLastVisibleRecordRefreshesQueuedUploadWithItsTombstone() throws {
        let stateURL = temporaryStateURL()
        let context = try makeTestContext()
        let task = TaskNode(title: "Delete before upload", parentID: nil, deviceID: "device-a")
        context.insert(task)
        try context.save()

        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let service = SyncConflictService(stateURL: stateURL)
            #expect(try service.forceUploadLocalData(context: context) == .queuedForNextLaunch)

            task.deletedAt = Date()
            task.updatedAt = Date()
            task.clientMutationID = UUID()
            try context.save()
            try service.recordLocalMutation(context: context, events: [.taskChanged(taskID: task.id, affectedAncestorIDs: [])])

            let queuedSnapshot = try #require(try service.loadPendingForcedUploadSnapshot())
            #expect(queuedSnapshot.tasks.count == 1)
            #expect(queuedSnapshot.tasks.first?.deletedAt != nil)
        }

        try withCloudSyncMode {
            let cloudContext = try makeTestContext()
            let cloudCopy = TaskNode(title: "Remote stale copy", parentID: nil, deviceID: "device-b")
            cloudCopy.id = task.id
            cloudContext.insert(cloudCopy)
            try cloudContext.save()

            let service = SyncConflictService(stateURL: stateURL)
            #expect(try service.bootstrap(context: cloudContext) == nil)
            let visibleTasks = try cloudContext.fetch(FetchDescriptor<TaskNode>())
                .filter { $0.deletedAt == nil }
            #expect(visibleTasks.isEmpty)
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
    func forceDownloadQueuesARealStoreResetEvenWhenCloudStorageIsActive() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Local cache row", parentID: nil, deviceID: "test"))
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())

            #expect(try service.acceptCurrentCloudData(context: context) == .queuedForNextLaunch)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey))
            #expect(try context.fetch(FetchDescriptor<TaskNode>()).contains { $0.deletedAt == nil })
            #expect(service.prompt() == nil)
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

    @Test @MainActor
    func recoveryPendingAndEphemeralModesBlockUserWrites() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            UserDefaults.standard.set(true, forKey: AppCloudSync.pendingCloudDownloadResetKey)
            #expect(AppCloudSync.allowsUserWrites == false)
            #expect(throws: PersistenceWriteError.self) {
                try AppCloudSync.requireUserWritesAllowed()
            }

            let context = try makeTestContext()
            #expect(throws: PersistenceWriteError.self) {
                try SystemActionCommandHandler().addInboxItem(title: "Must not persist", context: context)
            }
            #expect(try context.fetch(FetchDescriptor<InboxItem>()).isEmpty)
        }

        try withSyncMode(AppCloudSync.modeInMemoryFallback) {
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
            #expect(AppCloudSync.allowsUserWrites == false)
            #expect(throws: PersistenceWriteError.self) {
                try AppCloudSync.requireUserWritesAllowed()
            }
        }
    }

    @Test @MainActor
    func queuedUploadRecoveryStillAcceptsProtectedLocalWrites() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            UserDefaults.standard.set(true, forKey: AppCloudSync.pendingCloudUploadResetKey)
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)

            #expect(AppCloudSync.allowsUserWrites)
            try AppCloudSync.requireUserWritesAllowed()
        }
    }

    @Test @MainActor
    func fallbackMutationAutomaticallyQueuesProtectedCloudRecovery() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            UserDefaults.standard.set(true, forKey: AppCloudSync.enabledKey)
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)

            let context = try makeTestContext()
            let task = TaskNode(title: "Shared base", parentID: nil, deviceID: "device-a")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            task.title = "Edited while CloudKit was unavailable"
            task.updatedAt = Date().addingTimeInterval(60)
            task.clientMutationID = UUID()
            try context.save()
            try service.recordLocalMutation(
                context: context,
                events: [.taskChanged(taskID: task.id, affectedAncestorIDs: [])]
            )

            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            let queuedSnapshot = try #require(try service.loadPendingForcedUploadSnapshot())
            #expect(queuedSnapshot.tasks.map(\.title) == ["Edited while CloudKit was unavailable"])
        }
    }

    @Test @MainActor
    func enablingCloudImmediatelyProtectsCurrentLocalSnapshot() throws {
        try withSyncMode(AppCloudSync.modeLocal) {
            UserDefaults.standard.set(true, forKey: AppCloudSync.enabledKey)
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)

            let context = try makeTestContext()
            context.insert(TaskNode(title: "Local work before enabling Cloud", parentID: nil, deviceID: "device-a"))
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.stageCurrentLocalSnapshotForCloudEnablement(context: context) == .queuedForNextLaunch)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            let protectedSnapshot = try #require(try service.loadPendingForcedUploadSnapshot())
            #expect(protectedSnapshot.tasks.map(\.title) == ["Local work before enabling Cloud"])
        }
    }

    @Test @MainActor
    func ordinaryLocalMutationSkipsConflictStateAndSnapshotWork() throws {
        try withSyncMode(AppCloudSync.modeLocal) {
            UserDefaults.standard.set(false, forKey: AppCloudSync.enabledKey)
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            let stateURL = temporaryStateURL()
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let invalidState = Data("not valid sync state".utf8)
            try invalidState.write(to: stateURL, options: [.atomic])

            let context = try makeTestContext()
            context.insert(TaskNode(title: "Local only", parentID: nil, deviceID: "test"))
            try context.save()

            let service = SyncConflictService(stateURL: stateURL)
            try service.recordLocalMutation(context: context)

            #expect(try Data(contentsOf: stateURL) == invalidState)
        }
    }

    @Test @MainActor
    func corruptAuxiliaryStateIsQuarantinedAndFreshBaselineKeepsPrimaryDataAvailable() throws {
        try withCloudSyncMode {
            let stateURL = temporaryStateURL()
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("not valid sync state".utf8).write(to: stateURL, options: [.atomic])

            let context = try makeTestContext()
            context.insert(TaskNode(title: "Primary database task", parentID: nil, deviceID: "test"))
            try context.save()
            let service = SyncConflictService(stateURL: stateURL)

            #expect(throws: SyncConflictStateFileError.self) {
                try service.bootstrap(context: context)
            }
            #expect(FileManager.default.fileExists(atPath: stateURL.path) == false)

            let quarantinedFiles = try FileManager.default.contentsOfDirectory(
                at: stateURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(SyncConflictService.corruptStateFilePrefix) }
            #expect(quarantinedFiles.count == 1)

            #expect(try service.bootstrap(context: context) == nil)
            #expect(FileManager.default.fileExists(atPath: stateURL.path))
            let visibleTitles = try context.fetch(FetchDescriptor<TaskNode>())
                .filter { $0.deletedAt == nil }
                .map(\.title)
            #expect(visibleTitles == ["Primary database task"])
        }
    }

    @Test @MainActor
    func corruptRecoveryMirrorIsQuarantinedWithoutBlockingPrimaryData() throws {
        try withCloudSyncMode {
            let stateURL = temporaryStateURL()
            let service = SyncConflictService(stateURL: stateURL)
            let mirrorURL = try service.pendingForcedUploadSnapshotURL()
            try FileManager.default.createDirectory(
                at: mirrorURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("not a recovery snapshot".utf8).write(
                to: mirrorURL,
                options: [.atomic]
            )

            let context = try makeTestContext()
            context.insert(
                TaskNode(title: "Primary data survives", parentID: nil, deviceID: "test")
            )
            try context.save()

            #expect(try service.bootstrap(context: context) == nil)
            #expect(FileManager.default.fileExists(atPath: stateURL.path))
            #expect(FileManager.default.fileExists(atPath: mirrorURL.path) == false)
            let quarantinedMirrors = try FileManager.default.contentsOfDirectory(
                at: mirrorURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            ).filter {
                $0.lastPathComponent.hasPrefix(
                    SyncConflictService.corruptPendingSnapshotFilePrefix
                )
            }
            #expect(quarantinedMirrors.count == 1)
            let visibleTasks = try context.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID()
            #expect(visibleTasks.map(\.title) == ["Primary data survives"])
        }
    }

    @Test @MainActor
    func oversizedAuxiliaryStateIsQuarantinedWithoutReadingItIntoMemory() throws {
        let stateURL = temporaryStateURL()
        let oversizedByteCount = SyncConflictService.maximumStateFileByteCount + 1
        try writeSparseFile(byteCount: oversizedByteCount, to: stateURL)

        let service = SyncConflictService(stateURL: stateURL)
        #expect(throws: SyncConflictStateFileError.self) {
            try service.loadState()
        }
        #expect(FileManager.default.fileExists(atPath: stateURL.path) == false)

        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: stateURL.deletingLastPathComponent(),
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.lastPathComponent.hasPrefix(SyncConflictService.corruptStateFilePrefix) }
        let quarantinedFile = try #require(quarantinedFiles.first)
        #expect(quarantinedFiles.count == 1)
        #expect(
            try quarantinedFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
                == oversizedByteCount
        )
    }

    @Test @MainActor
    func oversizedRecoveryMirrorIsQuarantinedAndIgnored() throws {
        let stateURL = temporaryStateURL()
        let service = SyncConflictService(stateURL: stateURL)
        let mirrorURL = try service.pendingForcedUploadSnapshotURL()
        let oversizedByteCount = SyncConflictService.maximumRecoverySnapshotFileByteCount + 1
        try writeSparseFile(byteCount: oversizedByteCount, to: mirrorURL)

        let state = try service.loadState()
        #expect(state.pendingForcedUploadSnapshot == nil)
        #expect(FileManager.default.fileExists(atPath: mirrorURL.path) == false)

        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: mirrorURL.deletingLastPathComponent(),
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter {
            $0.lastPathComponent.hasPrefix(
                SyncConflictService.corruptPendingSnapshotFilePrefix
            )
        }
        let quarantinedFile = try #require(quarantinedFiles.first)
        #expect(quarantinedFiles.count == 1)
        #expect(
            try quarantinedFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
                == oversizedByteCount
        )
    }

    @Test @MainActor
    func staticRecoveryFallbackRejectsOversizedFileBeforeDecode() throws {
        let stateURL = temporaryStateURL()
        let service = SyncConflictService(stateURL: stateURL)
        let mirrorURL = try service.pendingForcedUploadSnapshotURL()
        try writeSparseFile(
            byteCount: SyncConflictService.maximumRecoverySnapshotFileByteCount + 1,
            to: mirrorURL
        )

        #expect(throws: SyncConflictLocalStateReadError.exceedsMaximumByteCount) {
            try SyncConflictService.loadPendingForcedUploadSnapshot(at: mirrorURL)
        }
        #expect(FileManager.default.fileExists(atPath: mirrorURL.path))
    }

    @Test @MainActor
    func cloudExportExcludesSensitiveAndDeviceLocalPreferences() throws {
        let context = try makeTestContext()
        context.insert(
            SyncedPreference(
                key: SyncedPreferenceService.legacyLLMAPIKey,
                valueJSON: PreferenceJSON.encode("secret-api-key"),
                deviceID: "test"
            )
        )
        context.insert(
            SyncedPreference(
                key: AppPreferenceKey.llmEndpoint.rawValue,
                valueJSON: PreferenceJSON.encode("https://example.test/v1"),
                deviceID: "test"
            )
        )
        context.insert(
            SyncedPreference(
                key: SyncedPreferenceService.legacyCloudSyncEnabledKey,
                valueJSON: PreferenceJSON.encode(false),
                deviceID: "test"
            )
        )
        try context.save()

        let service = SyncConflictService(stateURL: temporaryStateURL())
        let export = try service.exportCloudSyncedData(context: context)

        #expect(!export.contains("secret-api-key"))
        #expect(!export.contains(SyncedPreferenceService.legacyLLMAPIKey))
        #expect(!export.contains(SyncedPreferenceService.legacyCloudSyncEnabledKey))
        #expect(export.contains(AppPreferenceKey.llmEndpoint.rawValue))
    }

    @Test @MainActor
    func loadingLegacyConflictStateAtomicallyScrubsExcludedPreferences() throws {
        let stateURL = temporaryStateURL()
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let snapshot = snapshotJSONWithExcludedPreferences()
        let stateJSON = """
        {
          "baseFingerprint": "legacy-fingerprint",
          "localSnapshot": \(snapshot),
          "localFingerprint": "legacy-fingerprint",
          "pendingConflictID": "\(UUID().uuidString)",
          "pendingDetectedAt": \(Date().timeIntervalSinceReferenceDate),
          "pendingCloudSnapshot": \(snapshot)
        }
        """
        try Data(stateJSON.utf8).write(to: stateURL, options: [.atomic])

        let service = SyncConflictService(stateURL: stateURL)
        #expect(service.prompt() != nil)

        let rewrittenState = try String(contentsOf: stateURL, encoding: .utf8)
        #expect(!rewrittenState.contains("legacy-secret"))
        #expect(!rewrittenState.contains(SyncedPreferenceService.legacyLLMAPIKey))
        #expect(!rewrittenState.contains(SyncedPreferenceService.legacyCloudSyncEnabledKey))
    }

    @Test @MainActor
    func scrubbingLegacyPreferencesInvalidatesLegacyExportCheckpoints() throws {
        try withCloudSyncMode {
            let stateURL = temporaryStateURL()
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let eventID = UUID()
            let snapshot = snapshotJSONWithExcludedPreferences()
            let stateJSON = """
            {
              "baseFingerprint": "legacy-fingerprint",
              "localSnapshot": \(snapshot),
              "localFingerprint": "legacy-fingerprint",
              "syncEpoch": 7,
              "localGeneration": 3,
              "baseAcknowledgedGeneration": 3,
              "pendingCloudExportCheckpoints": {
                "\(eventID.uuidString)": {
                  "epoch": 7,
                  "generation": 3,
                  "fingerprint": "legacy-fingerprint",
                  "startedAt": \(Date().timeIntervalSinceReferenceDate)
                }
              }
            }
            """
            try Data(stateJSON.utf8).write(to: stateURL, options: [.atomic])

            let service = SyncConflictService(stateURL: stateURL)
            let migratedState = try service.loadState()
            let migratedBase = try #require(migratedState.baseFingerprint)
            #expect(migratedBase != "legacy-fingerprint")
            #expect(migratedState.pendingCloudExportCheckpoints == nil)

            // A delayed completion for the legacy payload must be ignored.
            try service.markCloudExportFinished(eventID: eventID, succeeded: true)
            #expect(try service.loadState().baseFingerprint == migratedBase)
        }
    }

    private func temporaryStateURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeTrackerSyncConflictTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        return url
    }

    private func writeSparseFile(byteCount: Int, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(byteCount))
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

    private func snapshotJSONWithExcludedPreferences() -> String {
        """
        {
          "tasks": [],
          "taskCategories": [],
          "taskCategoryAssignments": [],
          "sessions": [],
          "segments": [],
          "pomodoroRuns": [],
          "countdownEvents": [],
          "syncedPreferences": [
            {
              "id": "\(UUID().uuidString)",
              "key": "\(SyncedPreferenceService.legacyLLMAPIKey)",
              "valueJSON": "\\\"legacy-secret\\\"",
              "createdAt": 0,
              "updatedAt": 0,
              "deletedAt": null
            },
            {
              "id": "\(UUID().uuidString)",
              "key": "\(SyncedPreferenceService.legacyCloudSyncEnabledKey)",
              "valueJSON": "false",
              "createdAt": 0,
              "updatedAt": 0,
              "deletedAt": null
            }
          ],
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

    @MainActor
    private func acknowledgeCurrentCloudExport(
        service: SyncConflictService,
        context: ModelContext
    ) throws {
        let eventID = UUID()
        try service.markCloudExportStarted(eventID: eventID)
        try service.markCloudExportFinished(eventID: eventID, succeeded: true)
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

private nonisolated func waitForSemaphore(
    _ semaphore: DispatchSemaphore,
    timeout: DispatchTime
) async -> DispatchTimeoutResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: semaphore.wait(timeout: timeout))
        }
    }
}
