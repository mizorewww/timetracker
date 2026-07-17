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
            #expect(try service.prompt() == nil)
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
            #expect(try service.prompt() == nil)
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
            #expect(try service.prompt() == nil)
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
            let currentPrompt = try #require(try service.prompt())
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
            let currentPrompt = try #require(try service.prompt())
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
            #expect(try service.loadState().pendingLocalIntent == .explicitlyReplaceCloud)
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
            #expect(try service.prompt() == nil)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.enabledKey))
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            #expect(try service.loadState().pendingLocalIntent == .explicitlyReplaceCloud)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) == false)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.activeCloudReconciliationKey) == false)
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
            #expect(try service.prompt() == nil)
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
                try SystemActionCommandHandler().addInboxItem(
                    title: "Must not persist",
                    container: context.container
                )
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

            UserDefaults.standard.set(true, forKey: AppCloudSync.activeCloudReconciliationKey)
            #expect(AppCloudSync.allowsUserWrites == false)
            #expect(throws: PersistenceWriteError.self) {
                try AppCloudSync.requireUserWritesAllowed()
            }
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
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.queuedCloudReconciliationKey))
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.activeCloudReconciliationKey) == false)
            let queuedSnapshot = try #require(try service.loadPendingForcedUploadSnapshot())
            #expect(queuedSnapshot.tasks.map(\.title) == ["Edited while CloudKit was unavailable"])
            #expect(try service.loadState().pendingLocalIntent == .reconcileWithCloud)
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
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.queuedCloudReconciliationKey))
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.activeCloudReconciliationKey) == false)
            let protectedSnapshot = try #require(try service.loadPendingForcedUploadSnapshot())
            #expect(protectedSnapshot.tasks.map(\.title) == ["Local work before enabling Cloud"])
            #expect(try service.loadState().pendingLocalIntent == .reconcileWithCloud)
        }
    }

    @Test @MainActor
    func automaticCloudReenablePreservesRemoteDataUntilUserChooses() throws {
        try withSyncMode(AppCloudSync.modeLocal) {
            let service = SyncConflictService(stateURL: temporaryStateURL())
            let localContext = try makeTestContext()
            localContext.insert(TaskNode(title: "Protected local branch", parentID: nil, deviceID: "local"))
            try localContext.save()
            #expect(
                try service.stageCurrentLocalSnapshotForCloudEnablement(context: localContext) ==
                    .queuedForNextLaunch
            )

            UserDefaults.standard.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
            AppCloudSync.activateCloudReconciliation()
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            try recordCompletedInitialCloudImport(
                service: service,
                kind: .reconcileWithCloud
            )

            let cloudContext = try makeTestContext()
            cloudContext.insert(TaskNode(title: "Remote cloud branch", parentID: nil, deviceID: "remote"))
            try cloudContext.save()

            #expect(try service.bootstrap(context: cloudContext) == nil)
            #expect(
                try cloudContext.fetch(FetchDescriptor<TaskNode>())
                    .visibleDeduplicatedByID()
                    .map(\.title) == ["Remote cloud branch"]
            )
            #expect(AppCloudSync.allowsUserWrites == false)

            let prompt = try #require(try service.handleCloudImport(context: cloudContext))
            let state = try service.loadState()
            #expect(prompt.localSummary.isEmpty == false)
            #expect(prompt.cloudSummary.isEmpty == false)
            #expect(state.localSnapshot?.tasks.map(\.title) == ["Protected local branch"])
            #expect(state.pendingCloudSnapshot?.tasks.map(\.title) == ["Remote cloud branch"])
            #expect(state.pendingForcedUploadSnapshot == nil)
            #expect(state.pendingLocalIntent == nil)
            #expect(AppCloudSync.isCloudRecoveryPending == false)
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test @MainActor
    func matchingCloudCopyCompletesReconciliationWithoutPrompt() throws {
        try withSyncMode(AppCloudSync.modeLocal) {
            let service = SyncConflictService(stateURL: temporaryStateURL())
            let localContext = try makeTestContext()
            localContext.insert(TaskNode(title: "Already synchronized", parentID: nil, deviceID: "local"))
            try localContext.save()
            _ = try service.stageCurrentLocalSnapshotForCloudEnablement(context: localContext)

            UserDefaults.standard.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
            AppCloudSync.activateCloudReconciliation()
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            try recordCompletedInitialCloudImport(
                service: service,
                kind: .reconcileWithCloud
            )

            #expect(try service.bootstrap(context: localContext) == nil)
            #expect(try service.handleCloudImport(context: localContext) == nil)
            let state = try service.loadState()
            #expect(state.pendingForcedUploadSnapshot == nil)
            #expect(state.pendingLocalIntent == nil)
            #expect(state.pendingConflictID == nil)
            #expect(state.baseFingerprint == state.localFingerprint)
            #expect(AppCloudSync.isCloudRecoveryPending == false)
        }
    }

    @Test @MainActor
    func initialEmptyCloudImportPromptsBeforeProtectedLocalUpload() throws {
        try withSyncMode(AppCloudSync.modeLocal) {
            let service = SyncConflictService(stateURL: temporaryStateURL())
            let localContext = try makeTestContext()
            localContext.insert(TaskNode(title: "Device-only branch", parentID: nil, deviceID: "local"))
            try localContext.save()
            _ = try service.stageCurrentLocalSnapshotForCloudEnablement(context: localContext)

            UserDefaults.standard.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
            AppCloudSync.activateCloudReconciliation()
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            try recordCompletedInitialCloudImport(
                service: service,
                kind: .reconcileWithCloud
            )

            let emptyCloudContext = try makeTestContext()
            #expect(try service.bootstrap(context: emptyCloudContext) == nil)
            let prompt = try #require(try service.handleCloudImport(context: emptyCloudContext))
            let state = try service.loadState()

            #expect(prompt.localSummary.isEmpty == false)
            #expect(state.localSnapshot?.tasks.map(\.title) == ["Device-only branch"])
            #expect(state.pendingCloudSnapshot?.hasProtectableUserContent == false)
            #expect(state.pendingForcedUploadSnapshot == nil)
            #expect(AppCloudSync.isCloudReconciliationActive == false)
        }
    }

    @Test @MainActor
    func legacyPendingSnapshotWithoutIntentReconcilesInsteadOfReplacingCloud() throws {
        try withSyncMode(AppCloudSync.modeLocal) {
            let service = SyncConflictService(stateURL: temporaryStateURL())
            let localContext = try makeTestContext()
            localContext.insert(TaskNode(title: "Legacy local branch", parentID: nil, deviceID: "local"))
            try localContext.save()
            _ = try service.stageCurrentLocalSnapshotForCloudEnablement(context: localContext)
            var legacyState = try service.loadState()
            legacyState.pendingLocalIntent = nil
            try service.saveState(legacyState)

            let cloudContext = try makeTestContext()
            cloudContext.insert(TaskNode(title: "Current remote branch", parentID: nil, deviceID: "remote"))
            try cloudContext.save()
            UserDefaults.standard.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
            AppCloudSync.activateCloudReconciliation()
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            try recordCompletedInitialCloudImport(
                service: service,
                kind: .reconcileWithCloud
            )

            #expect(try service.bootstrap(context: cloudContext) == nil)
            #expect(try service.loadState().pendingLocalIntent == .reconcileWithCloud)
            #expect(
                try cloudContext.fetch(FetchDescriptor<TaskNode>())
                    .visibleDeduplicatedByID()
                    .map(\.title) == ["Current remote branch"]
            )
            #expect(try service.handleCloudImport(context: cloudContext) != nil)
        }
    }

    @Test @MainActor
    func explicitForceUploadSupersedesQueuedReconciliation() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Explicit local winner", parentID: nil, deviceID: "local"))
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())

            _ = try service.stageCurrentLocalSnapshotForCloudEnablement(context: context)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.queuedCloudReconciliationKey))
            #expect(try service.forceUploadLocalData(context: context) == .queuedForNextLaunch)

            let state = try service.loadState()
            #expect(state.pendingLocalIntent == .explicitlyReplaceCloud)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudUploadResetKey))
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) == false)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.activeCloudReconciliationKey) == false)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey) == false)
        }
    }

    @Test @MainActor
    func reconciliationIgnoresCloudExportAcknowledgements() throws {
        try withSyncMode(AppCloudSync.modeLocal) {
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Unreviewed local branch", parentID: nil, deviceID: "local"))
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            _ = try service.stageCurrentLocalSnapshotForCloudEnablement(context: context)
            UserDefaults.standard.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
            AppCloudSync.activateCloudReconciliation()

            let eventID = UUID()
            try service.markCloudExportStarted(eventID: eventID)
            try service.markCloudExportFinished(eventID: eventID, succeeded: true)

            let state = try service.loadState()
            #expect(state.pendingForcedUploadSnapshot != nil)
            #expect(state.pendingLocalIntent == .reconcileWithCloud)
            #expect(state.pendingCloudExportCheckpoints == nil)
            #expect(AppCloudSync.isCloudReconciliationActive)
        }
    }

    @Test @MainActor
    func staleActiveMarkerIsClearedFromAuthoritativeCompletedState() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Cloud data", parentID: nil, deviceID: "remote"))
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            AppCloudSync.activateCloudReconciliation()

            #expect(try service.bootstrap(context: context) == nil)
            #expect(AppCloudSync.isCloudReconciliationActive == false)
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test @MainActor
    func successfulCloudImportCompletesDownloadRecovery() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Downloaded cloud branch", parentID: nil, deviceID: "remote"))
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            UserDefaults.standard.set(true, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
            try recordCompletedInitialCloudImport(
                service: service,
                kind: .downloadCloud
            )

            #expect(try service.bootstrap(context: context) == nil)
            #expect(AppCloudSync.allowsUserWrites == false)
            #expect(try service.handleCloudImport(context: context) == nil)

            let state = try service.loadState()
            #expect(state.cloudDownloadRecoveryCompleted == true)
            #expect(AppCloudSync.isCloudDownloadRecoveryActive == false)
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test @MainActor
    func successfulInitialImportCompletesAnEmptyCloudDownload() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            UserDefaults.standard.set(true, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
            try recordCompletedInitialCloudImport(
                service: service,
                kind: .downloadCloud
            )

            #expect(try service.bootstrap(context: context) == nil)
            #expect(try service.handleCloudImport(context: context) == nil)

            let state = try service.loadState()
            #expect(state.localSnapshot?.hasProtectableUserContent == false)
            #expect(state.cloudDownloadRecoveryCompleted == true)
            #expect(AppCloudSync.isCloudDownloadRecoveryActive == false)
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test @MainActor
    func unjournaledCloudImportCannotCompleteDownloadRecovery() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Unverified cloud cache", parentID: nil, deviceID: "remote"))
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            UserDefaults.standard.set(true, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)

            #expect(try service.bootstrap(context: context) == nil)
            #expect(try service.handleCloudImport(context: context) == nil)

            #expect(AppCloudSync.isCloudDownloadRecoveryActive)
            #expect(AppCloudSync.allowsUserWrites == false)
            #expect(try service.loadState().cloudDownloadRecoveryCompleted != true)
        }
    }

    @Test @MainActor
    func attachedCloudRecoveryRejectsStaleDirectionalCommands() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Hydrating cloud cache", parentID: nil, deviceID: "remote"))
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            UserDefaults.standard.set(true, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)

            #expect(throws: SyncConflictError.self) {
                try service.forceUploadLocalData(context: context)
            }
            #expect(throws: SyncConflictError.self) {
                try service.acceptCurrentCloudData(context: context)
            }
            #expect(throws: SyncConflictError.self) {
                try service.resolveSyncConflict(
                    expectedConflictID: nil,
                    resolution: .uploadLocal,
                    context: context
                )
            }
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudUploadResetKey) == false)
            #expect(UserDefaults.standard.bool(forKey: AppCloudSync.pendingCloudDownloadResetKey) == false)
            #expect(AppCloudSync.isCloudDownloadRecoveryActive)
        }
    }

    @Test @MainActor
    func wrongRecoverySessionKindCannotUnlockTheActiveGate() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            UserDefaults.standard.set(true, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
            try recordCompletedInitialCloudImport(
                service: service,
                kind: .reconcileWithCloud
            )

            #expect(try service.handleCloudImport(context: context) == nil)
            #expect(AppCloudSync.isCloudDownloadRecoveryActive)
            #expect(try service.loadState().cloudDownloadRecoveryCompleted != true)
            #expect(AppCloudSync.allowsUserWrites == false)
        }

        try withCloudSyncMode {
            let context = try makeTestContext()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            AppCloudSync.activateCloudReconciliation()
            try recordCompletedInitialCloudImport(
                service: service,
                kind: .downloadCloud
            )

            #expect(try service.handleCloudImport(context: context) == nil)
            #expect(AppCloudSync.isCloudReconciliationActive)
            #expect(try service.loadState().cloudRecoveryImportSession?.kind == .downloadCloud)
            #expect(AppCloudSync.allowsUserWrites == false)
        }
    }

    @Test @MainActor
    func completedDownloadRecoveryMarkerConvergesAfterCrash() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Imported before crash", parentID: nil, deviceID: "remote"))
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            var state = SyncConflictState()
            state.cloudDownloadRecoveryCompleted = true
            try service.saveState(state)
            UserDefaults.standard.set(true, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)

            #expect(try service.bootstrap(context: context) == nil)
            #expect(AppCloudSync.isCloudDownloadRecoveryActive == false)
            #expect(try service.loadState().cloudDownloadRecoveryCompleted == nil)
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test @MainActor
    func olderImportIsProcessedBeforeExplicitExportAcknowledgement() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Explicit local winner", parentID: nil, deviceID: "local")
            context.insert(task)
            try context.save()
            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.forceUploadLocalData(context: context) == .appliedImmediately)
            let eventID = UUID()
            try service.markCloudExportStarted(eventID: eventID)

            task.title = "Older imported cloud copy"
            task.updatedAt = Date().addingTimeInterval(-60)
            task.clientMutationID = UUID()
            try context.save()

            #expect(try service.handleCloudImport(context: context) == nil)
            try service.markCloudExportFinished(eventID: eventID, succeeded: true)

            let restored = try #require(
                try context.fetch(FetchDescriptor<TaskNode>()).visibleDeduplicatedByID().first
            )
            let state = try service.loadState()
            #expect(restored.title == "Explicit local winner")
            #expect(state.pendingLocalIntent == .explicitlyReplaceCloud)
            #expect(state.pendingForcedUploadSnapshot != nil)
        }
    }

    @Test @MainActor
    func recoveryOnlyStoreConfigurationDefersStartupMigrations() throws {
        try withSyncMode(AppCloudSync.modeLocal) {
            let defaults = UserDefaults.standard
            let previousPayload = defaults.object(forKey: LegacyCountdownMigrationPolicy.payloadKey)
            let previousMigration = defaults.object(forKey: LegacyCountdownMigrationPolicy.migrationKey)
            defer {
                if let previousPayload {
                    defaults.set(previousPayload, forKey: LegacyCountdownMigrationPolicy.payloadKey)
                } else {
                    defaults.removeObject(forKey: LegacyCountdownMigrationPolicy.payloadKey)
                }
                if let previousMigration {
                    defaults.set(previousMigration, forKey: LegacyCountdownMigrationPolicy.migrationKey)
                } else {
                    defaults.removeObject(forKey: LegacyCountdownMigrationPolicy.migrationKey)
                }
            }

            let service = SyncConflictService(stateURL: temporaryStateURL())
            let localContext = try makeTestContext()
            localContext.insert(TaskNode(title: "Protected local branch", parentID: nil, deviceID: "local"))
            try localContext.save()
            _ = try service.stageCurrentLocalSnapshotForCloudEnablement(context: localContext)

            let cloudContext = try makeTestContext()
            let remoteTask = TaskNode(title: "Remote branch", parentID: nil, deviceID: "remote")
            cloudContext.insert(remoteTask)
            let activeRun = PomodoroRun(
                taskID: remoteTask.id,
                focus: 1_500,
                breakSeconds: 300,
                longBreakSeconds: 900,
                targetRounds: 4,
                deviceID: "remote"
            )
            activeRun.state = .focusing
            activeRun.startedAt = Date()
            cloudContext.insert(activeRun)
            try cloudContext.save()
            defaults.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
            defaults.set("[]", forKey: LegacyCountdownMigrationPolicy.payloadKey)
            defaults.removeObject(forKey: LegacyCountdownMigrationPolicy.migrationKey)
            AppCloudSync.activateCloudReconciliation()

            let store = TimeTrackerStore(syncConflictService: service)
            store.configureIfNeeded(context: cloudContext)

            #expect(store.taskRepository != nil)
            #expect(store.syncObservers.isEmpty == false)
            #expect(store.hasCompletedStartupConfiguration == false)
            #expect(store.persistenceWriteSafety != .ready)
            #expect(store.pomodoroReconciliationTask == nil)
            #expect(store.cloudAccountCheckRequestID == nil)
            #expect(defaults.string(forKey: LegacyCountdownMigrationPolicy.payloadKey) == "[]")
            #expect(defaults.bool(forKey: LegacyCountdownMigrationPolicy.migrationKey) == false)
            #expect(try cloudContext.fetch(FetchDescriptor<CountdownEvent>()).isEmpty)
        }
    }

    @Test @MainActor
    func recoveryBootstrapRetriesCorruptStateAndRestoresExplicitWinnerOnlyOnce() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let stateURL = temporaryStateURL()
            let service = SyncConflictService(stateURL: stateURL)
            let localContext = try makeTestContext()
            localContext.insert(TaskNode(title: "Protected explicit winner", parentID: nil, deviceID: "local"))
            try localContext.save()
            #expect(try service.forceUploadLocalData(context: localContext) == .queuedForNextLaunch)

            let before = try service.loadState()
            try Data("corrupt primary state".utf8).write(to: stateURL, options: [.atomic])
            UserDefaults.standard.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            UserDefaults.standard.set(true, forKey: AppCloudSync.cloudRecoveryStoreResetKey)

            let cloudContext = try makeTestContext()
            let store = TimeTrackerStore(syncConflictService: service)
            store.configureIfNeeded(context: cloudContext)

            let restoredTitles = try cloudContext.fetch(FetchDescriptor<TaskNode>())
                .visibleDeduplicatedByID()
                .map(\.title)
            let after = try service.loadState()
            #expect(restoredTitles.contains("Protected explicit winner"))
            #expect(store.hasCompletedStartupConfiguration)
            #expect(store.hasBootstrappedSyncConflictState)
            #expect(before.syncEpoch != nil)
            #expect(before.localGeneration != nil)
            #expect(after.syncEpoch == 1)
            #expect(after.localGeneration == 1)
            #expect(after.pendingLocalIntent == .explicitlyReplaceCloud)
            #expect(AppCloudSync.allowsUserWrites)
        }
    }

    @Test @MainActor
    func recoveryMirrorKeepsQueuedReconciliationConservative() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let stateURL = temporaryStateURL()
            let service = SyncConflictService(stateURL: stateURL)
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Fallback branch", parentID: nil, deviceID: "local"))
            try context.save()
            _ = try service.stageCurrentLocalSnapshotForCloudEnablement(context: context)

            try Data("corrupt primary state".utf8).write(to: stateURL, options: [.atomic])
            #expect(throws: SyncConflictStateFileError.self) {
                try service.loadState()
            }
            let recovered = try service.loadState()

            #expect(recovered.pendingForcedUploadSnapshot?.tasks.map(\.title) == ["Fallback branch"])
            #expect(recovered.pendingLocalIntent == .reconcileWithCloud)
        }
    }

    @Test @MainActor
    func recoveryMirrorWithoutIntentMarkersDefaultsToReconciliation() throws {
        try withSyncMode(AppCloudSync.modeLocalFallback) {
            let stateURL = temporaryStateURL()
            let service = SyncConflictService(stateURL: stateURL)
            let context = try makeTestContext()
            context.insert(TaskNode(title: "Unmarked protected branch", parentID: nil, deviceID: "local"))
            try context.save()
            _ = try service.stageCurrentLocalSnapshotForCloudEnablement(context: context)

            UserDefaults.standard.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
            UserDefaults.standard.removeObject(forKey: AppCloudSync.queuedCloudReconciliationKey)
            try Data("corrupt primary state".utf8).write(to: stateURL, options: [.atomic])
            #expect(throws: SyncConflictStateFileError.self) {
                try service.loadState()
            }
            let recovered = try service.loadState()

            #expect(recovered.pendingLocalIntent == .reconcileWithCloud)
        }
    }

    @Test @MainActor
    func recoveryCompletionBroadcastUpdatesEveryConfiguredSceneStore() throws {
        try withSyncMode(AppCloudSync.modeLocal) {
            let service = SyncConflictService(stateURL: temporaryStateURL())
            let context = try makeTestContext()
            let task = TaskNode(title: "Protected local branch", parentID: nil, deviceID: "local")
            context.insert(task)
            try context.save()
            _ = try service.stageCurrentLocalSnapshotForCloudEnablement(context: context)

            task.title = "Imported remote branch"
            task.updatedAt = Date().addingTimeInterval(60)
            task.clientMutationID = UUID()
            try context.save()
            UserDefaults.standard.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
            AppCloudSync.activateCloudReconciliation()
            try recordCompletedInitialCloudImport(
                service: service,
                kind: .reconcileWithCloud
            )

            let firstStore = TimeTrackerStore(syncConflictService: service)
            let secondStore = TimeTrackerStore(syncConflictService: service)
            firstStore.configureIfNeeded(context: context)
            secondStore.configureIfNeeded(context: context)
            #expect(firstStore.persistenceWriteSafety != .ready)
            #expect(secondStore.persistenceWriteSafety != .ready)

            let prompt = try #require(try service.handleCloudImport(context: context))

            #expect(firstStore.persistenceWriteSafety == .ready)
            #expect(secondStore.persistenceWriteSafety == .ready)
            #expect(firstStore.pendingSyncConflict?.id == prompt.id)
            #expect(secondStore.pendingSyncConflict?.id == prompt.id)
            #expect(firstStore.hasCompletedStartupConfiguration == false)
            #expect(secondStore.hasCompletedStartupConfiguration == false)
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

            let quarantinedFiles = try quarantineEntries(
                near: stateURL,
                prefix: SyncConflictService.corruptStateFilePrefix
            )
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
    func promptSurfacesCorruptStateInsteadOfReportingNoConflict() throws {
        let stateURL = temporaryStateURL()
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not valid sync state".utf8).write(to: stateURL, options: [.atomic])
        let service = SyncConflictService(stateURL: stateURL)

        #expect(throws: SyncConflictStateFileError.self) {
            _ = try service.prompt()
        }
        #expect(FileManager.default.fileExists(atPath: stateURL.path) == false)
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
            let quarantinedMirrors = try quarantineEntries(
                near: mirrorURL,
                prefix: SyncConflictService.corruptPendingSnapshotFilePrefix
            )
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

        #expect(
            try quarantineEntries(
                near: stateURL,
                prefix: SyncConflictService.corruptStateFilePrefix
            ).isEmpty
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

        #expect(
            try quarantineEntries(
                near: mirrorURL,
                prefix: SyncConflictService.corruptPendingSnapshotFilePrefix
            ).isEmpty
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
        #expect(try service.prompt() != nil)

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

    private func quarantineEntries(near url: URL, prefix: String) throws -> [URL] {
        let quarantineDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(".TimeTrackerQuarantine", isDirectory: true)
        guard FileManager.default.fileExists(atPath: quarantineDirectory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: quarantineDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(prefix) }
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
        let previousQueuedReconciliation = defaults.object(forKey: AppCloudSync.queuedCloudReconciliationKey)
        let previousActiveReconciliation = defaults.object(forKey: AppCloudSync.activeCloudReconciliationKey)
        let previousCloudRecoveryStoreReset = defaults.object(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
        let previousActiveCloudDownloadRecovery = defaults.object(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
        defaults.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
        defaults.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
        defaults.removeObject(forKey: AppCloudSync.queuedCloudReconciliationKey)
        defaults.removeObject(forKey: AppCloudSync.activeCloudReconciliationKey)
        defaults.removeObject(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
        defaults.removeObject(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
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
            if let previousQueuedReconciliation {
                defaults.set(previousQueuedReconciliation, forKey: AppCloudSync.queuedCloudReconciliationKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.queuedCloudReconciliationKey)
            }
            if let previousActiveReconciliation {
                defaults.set(previousActiveReconciliation, forKey: AppCloudSync.activeCloudReconciliationKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.activeCloudReconciliationKey)
            }
            if let previousCloudRecoveryStoreReset {
                defaults.set(previousCloudRecoveryStoreReset, forKey: AppCloudSync.cloudRecoveryStoreResetKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
            }
            if let previousActiveCloudDownloadRecovery {
                defaults.set(previousActiveCloudDownloadRecovery, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
            }
        }
        try body()
    }

    @MainActor
    private func recordCompletedInitialCloudImport(
        service: SyncConflictService,
        kind: CloudRecoveryImportKind,
        storeIdentifier: String = "test-cloud-store"
    ) throws {
        let sessionStartedAt = Date(timeIntervalSince1970: 10_000)
        try service.beginCloudRecoveryImportSession(
            kind: kind,
            startedAt: sessionStartedAt
        )
        try service.recordCloudRecoveryContainerEvent(
            CloudRecoveryContainerEventReceipt(
                storeIdentifier: storeIdentifier,
                kind: .setup,
                startedAt: sessionStartedAt.addingTimeInterval(1),
                completedAt: sessionStartedAt.addingTimeInterval(2),
                succeeded: true
            )
        )
        try service.recordCloudRecoveryContainerEvent(
            CloudRecoveryContainerEventReceipt(
                storeIdentifier: storeIdentifier,
                kind: .import,
                startedAt: sessionStartedAt.addingTimeInterval(3),
                completedAt: sessionStartedAt.addingTimeInterval(4),
                succeeded: true
            )
        )
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
