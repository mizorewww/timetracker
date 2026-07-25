import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct CoreTaskDraftRecoveryStoreTests {
    @Test
    func existingDirtyDraftRoundTripsAcrossStoreInstances() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Original")
        let current = source.draft()
        var dirty = current
        dirty.title = "Recovered title"
        dirty.notes = "Recovered **Markdown**"
        dirty.checklistItems[0].title = "Recovered checklist item"
        let savedAt = Date(timeIntervalSince1970: 10000)

        try disk.store(now: savedAt).save(dirty, for: source.task.id)
        let loadedDraft = try disk.store(
            now: savedAt.addingTimeInterval(1)
        ).load(
            for: source.task.id,
            currentDraft: current
        )
        let recovered = try #require(loadedDraft)

        #expect(recovered == dirty)
        #expect(recovered.id == dirty.id)
        #expect(recovered.baseline == dirty.baseline)
        #expect(recovered.checklistItems[0].id == dirty.checklistItems[0].id)
        #expect(
            recovered.checklistItems[0].existingID ==
                dirty.checklistItems[0].existingID
        )

        try disk.store(now: savedAt).remove(for: source.task.id)
        #expect(
            try FileManager.default.fileExists(
                atPath: disk.store(now: savedAt)
                    .fileURL(for: source.task.id).path
            ) == false
        )
    }

    @Test
    func semanticallyCleanDraftIsNotRecoveredAndIsRemoved() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Clean")
        let savedDraft = source.draft()
        let freshlyLoadedCurrentDraft = source.draft()
        #expect(savedDraft.id != freshlyLoadedCurrentDraft.id)
        let store = disk.store()
        try store.save(savedDraft, for: source.task.id)
        let fileURL = try store.fileURL(for: source.task.id)

        #expect(
            try store.load(
                for: source.task.id,
                currentDraft: freshlyLoadedCurrentDraft
            ) == nil
        )
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func committedEditableContentIgnoresTheSupersededMutationBaseline() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Committed")
        let savedDraft = source.draft()
        let store = disk.store()
        try store.save(savedDraft, for: source.task.id)
        let fileURL = try store.fileURL(for: source.task.id)
        source.task.clientMutationID = UUID()
        let currentDraft = source.draft()
        #expect(savedDraft.baseline != currentDraft.baseline)

        #expect(
            try store.load(
                for: source.task.id,
                currentDraft: currentDraft
            ) == nil
        )
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func committedNewChecklistIgnoresEditorAndPersistentIdentities() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Committed checklist")
        var savedDraft = source.draft()
        let newDraftItem = ChecklistEditorDraft(
            title: "New committed item",
            isCompleted: true,
            iconName: "figure.strengthtraining.traditional",
            colorHex: "FF9500"
        )
        savedDraft.checklistItems.append(newDraftItem)
        let store = disk.store()
        try store.save(savedDraft, for: source.task.id)
        let fileURL = try store.fileURL(for: source.task.id)

        let committedItem = ChecklistItem(
            taskID: source.task.id,
            title: newDraftItem.title,
            isCompleted: newDraftItem.isCompleted,
            sortOrder: 20,
            deviceID: "draft-recovery-tests"
        )
        let committedVisual = ChecklistItemVisual(
            checklistItemID: committedItem.id,
            iconName: newDraftItem.iconName,
            colorHex: newDraftItem.colorHex,
            deviceID: "draft-recovery-tests"
        )
        source.task.clientMutationID = UUID()
        let currentDraft = TaskEditorDraft(
            task: source.task,
            checklistItems: [source.checklistItem, committedItem],
            visualByChecklistID: [
                source.checklistItem.id: source.visual,
                committedItem.id: committedVisual,
            ]
        )

        #expect(newDraftItem.id != committedItem.id)
        #expect(newDraftItem.existingID == nil)
        #expect(currentDraft.checklistItems.last?.existingID == committedItem.id)
        #expect(
            try store.load(
                for: source.task.id,
                currentDraft: currentDraft
            ) == nil
        )
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func corruptFileIsIgnoredAndRemoved() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Corrupt")
        let store = disk.store()
        let fileURL = try store.fileURL(for: source.task.id)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        #expect(
            try store.load(
                for: source.task.id,
                currentDraft: source.draft()
            ) == nil
        )
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func expiredFileIsIgnoredAndRemoved() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Expired")
        let savedAt = Date(timeIntervalSince1970: 20000)
        var dirty = source.draft()
        dirty.title = "Unsaved"
        let writer = disk.store(now: savedAt, retentionInterval: 60)
        try writer.save(dirty, for: source.task.id)
        let fileURL = try writer.fileURL(for: source.task.id)

        let recovered = try disk.store(
            now: savedAt.addingTimeInterval(61),
            retentionInterval: 60
        ).load(for: source.task.id, currentDraft: source.draft())

        #expect(recovered == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func taskMismatchedFileIsIgnoredAndRemoved() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let first = ExistingTaskFixture(title: "First")
        let second = ExistingTaskFixture(title: "Second")
        var firstDirty = first.draft()
        firstDirty.title = "First dirty"
        let store = disk.store()
        try store.save(firstDirty, for: first.task.id)
        let firstURL = try store.fileURL(for: first.task.id)
        let mismatchedURL = try store.fileURL(for: second.task.id)
        try FileManager.default.copyItem(at: firstURL, to: mismatchedURL)

        #expect(
            try store.load(
                for: second.task.id,
                currentDraft: second.draft()
            ) == nil
        )
        #expect(FileManager.default.fileExists(atPath: mismatchedURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
    }

    @Test
    func encodedSizeLimitRejectsOversizedDraftWithoutPublishingAFile() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Bounded")
        var dirty = source.draft()
        dirty.notes = String(repeating: "x", count: 2048)
        let store = disk.store(maximumEncodedByteCount: 512)

        #expect(throws: TaskDraftRecoveryStoreError.self) {
            try store.save(dirty, for: source.task.id)
        }
        #expect(
            try FileManager.default.fileExists(
                atPath: store.fileURL(for: source.task.id).path
            ) == false
        )
    }

    @Test
    func invalidCurrentDraftNeverDeletesAValidRecoveryFile() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Valid recovery")
        let current = source.draft()
        var dirty = current
        dirty.title = "Keep this"
        let store = disk.store()
        try store.save(dirty, for: source.task.id)
        let fileURL = try store.fileURL(for: source.task.id)

        #expect(throws: TaskDraftRecoveryStoreError.invalidExistingTaskDraft) {
            try store.load(
                for: source.task.id,
                currentDraft: TaskEditorDraft(parentID: nil)
            )
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(
            try store.load(
                for: source.task.id,
                currentDraft: current
            ) == dirty
        )
    }

    @Test
    func transientReadFailuresPreserveTheOnlyRecoveryFile() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Transient failure")
        let current = source.draft()
        var dirty = current
        dirty.title = "Do not delete"
        let writer = disk.store()
        try writer.save(dirty, for: source.task.id)
        let fileURL = try writer.fileURL(for: source.task.id)
        let failingFile = DurableLocalFile(injectFault: { point in
            if point == .beforeManagedRead {
                throw InjectedReadFailure()
            }
        })
        let failingStore = disk.store(localFile: failingFile)

        #expect(throws: InjectedReadFailure.self) {
            try failingStore.load(
                for: source.task.id,
                currentDraft: current
            )
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(throws: InjectedReadFailure.self) {
            try failingStore.removeExpired()
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(
            try disk.store().load(
                for: source.task.id,
                currentDraft: current
            ) == dirty
        )
    }

    @Test
    func oversizedRecoveryFileIsConfirmedInvalidBeforeRemoval() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Oversized recovery")
        let current = source.draft()
        var dirty = current
        dirty.notes = String(repeating: "x", count: 2048)
        let writer = disk.store()
        try writer.save(dirty, for: source.task.id)
        let fileURL = try writer.fileURL(for: source.task.id)

        #expect(
            try disk.store(maximumEncodedByteCount: 512).load(
                for: source.task.id,
                currentDraft: current
            ) == nil
        )
        #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
    }

    @Test
    func recoverableRecordsDoNotRequireCurrentTasksAndSortDeterministically() async throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let first = ExistingTaskFixture(title: "First tied recovery")
        let second = ExistingTaskFixture(title: "Second tied recovery")
        let older = ExistingTaskFixture(title: "Older recovery")
        let tiedSavedAt = Date(timeIntervalSince1970: 30000)
        let olderSavedAt = tiedSavedAt.addingTimeInterval(-1)
        let tiedSources = [first, second].sorted {
            $0.task.id.uuidString < $1.task.id.uuidString
        }

        for source in [first, second] {
            var draft = source.draft()
            draft.title += " unsaved"
            try disk.store(now: tiedSavedAt).save(
                draft,
                for: source.task.id
            )
        }
        var olderDraft = older.draft()
        olderDraft.title += " unsaved"
        try disk.store(now: olderSavedAt).save(
            olderDraft,
            for: older.task.id
        )

        let store = disk.store(
            now: tiedSavedAt.addingTimeInterval(1)
        )
        let records = try store.recoverableRecords()
        let expectedIDs = tiedSources.map(\.task.id) + [older.task.id]

        #expect(records.map(\.sourceTaskID) == expectedIDs)
        #expect(records.map(\.savedAt) == [
            tiedSavedAt,
            tiedSavedAt,
            olderSavedAt,
        ])
        #expect(
            records.map(\.draft.title) ==
                tiedSources.map { $0.task.title + " unsaved" } +
                [older.task.title + " unsaved"]
        )

        let controller = TaskDraftRecoveryController(store: store)
        #expect(
            try await controller.recoverableRecords() == records
        )
    }

    @Test
    func recoverableRecordsValidateEveryEnvelopeIdentityAndExpiry() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let now = Date(timeIntervalSince1970: 40000)
        let valid = ExistingTaskFixture(title: "Valid")
        var validDraft = valid.draft()
        validDraft.title = "Keep valid recovery"
        let store = disk.store(now: now, retentionInterval: 60)
        try store.save(validDraft, for: valid.task.id)

        let unsupported = ExistingTaskFixture(title: "Unsupported schema")
        let unsupportedURL = try disk.writeEnvelope(
            TaskDraftRecoveryEnvelope(
                schemaVersion:
                TaskDraftRecoveryStore.currentSchemaVersion + 1,
                sourceTaskID: unsupported.task.id,
                savedAt: now,
                draft: unsupported.draft()
            ),
            fileNameTaskID: unsupported.task.id
        )

        let mismatchedDraft = ExistingTaskFixture(title: "Mismatched draft")
        let other = ExistingTaskFixture(title: "Other task")
        let mismatchedDraftURL = try disk.writeEnvelope(
            TaskDraftRecoveryEnvelope(
                schemaVersion:
                TaskDraftRecoveryStore.currentSchemaVersion,
                sourceTaskID: mismatchedDraft.task.id,
                savedAt: now,
                draft: other.draft()
            ),
            fileNameTaskID: mismatchedDraft.task.id
        )

        let missingBaselineID = UUID()
        var missingBaselineDraft = TaskEditorDraft(parentID: nil)
        missingBaselineDraft.taskID = missingBaselineID
        let missingBaselineURL = try disk.writeEnvelope(
            TaskDraftRecoveryEnvelope(
                schemaVersion:
                TaskDraftRecoveryStore.currentSchemaVersion,
                sourceTaskID: missingBaselineID,
                savedAt: now,
                draft: missingBaselineDraft
            ),
            fileNameTaskID: missingBaselineID
        )

        let mismatchedFile = ExistingTaskFixture(title: "Mismatched file")
        let mismatchedFileURL = try disk.writeEnvelope(
            TaskDraftRecoveryEnvelope(
                schemaVersion:
                TaskDraftRecoveryStore.currentSchemaVersion,
                sourceTaskID: mismatchedFile.task.id,
                savedAt: now,
                draft: mismatchedFile.draft()
            ),
            fileNameTaskID: UUID()
        )

        let expired = ExistingTaskFixture(title: "Expired")
        let expiredURL = try disk.writeEnvelope(
            TaskDraftRecoveryEnvelope(
                schemaVersion:
                TaskDraftRecoveryStore.currentSchemaVersion,
                sourceTaskID: expired.task.id,
                savedAt: now.addingTimeInterval(-61),
                draft: expired.draft()
            ),
            fileNameTaskID: expired.task.id
        )

        let records = try store.recoverableRecords()

        #expect(records.map(\.sourceTaskID) == [valid.task.id])
        #expect(records.first?.draft == validDraft)
        for invalidURL in [
            unsupportedURL,
            mismatchedDraftURL,
            missingBaselineURL,
            mismatchedFileURL,
            expiredURL,
        ] {
            #expect(
                FileManager.default.fileExists(
                    atPath: invalidURL.path
                ) == false
            )
        }
    }

    @Test
    func recoverableRecordsRemoveConfirmedCorruptAndOversizedFiles() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let store = disk.store(maximumEncodedByteCount: 512)
        let corruptURL = try disk.write(
            Data("not-json".utf8),
            fileNameTaskID: UUID()
        )
        let oversizedURL = try disk.write(
            Data(repeating: 0x78, count: 513),
            fileNameTaskID: UUID()
        )

        #expect(try store.recoverableRecords().isEmpty)
        #expect(
            FileManager.default.fileExists(
                atPath: corruptURL.path
            ) == false
        )
        #expect(
            FileManager.default.fileExists(
                atPath: oversizedURL.path
            ) == false
        )
    }

    @Test
    func recoverableRecordTransientReadFailurePreservesFileAndThrows() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Transient enumeration")
        var draft = source.draft()
        draft.title = "Do not delete during transient failure"
        let writer = disk.store()
        try writer.save(draft, for: source.task.id)
        let fileURL = try writer.fileURL(for: source.task.id)
        let failure = DurableLocalFile(injectFault: { point in
            if point == .beforeManagedRead {
                throw InjectedReadFailure()
            }
        })

        #expect(throws: InjectedReadFailure.self) {
            try disk.store(localFile: failure).recoverableRecords()
        }
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(
            try writer.recoverableRecords().map(\.draft) == [draft]
        )
    }

    @Test
    func controllerPerformsRoutinePersistenceOffTheMainActor() async throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Background persistence")
        let current = source.draft()
        var dirty = current
        dirty.title = "Saved away from UI"
        let threadProbe = ThreadProbe()
        let localFile = DurableLocalFile(injectFault: { point in
            if point == .afterAtomicWriteBeforeFileSync {
                threadProbe.record(Thread.isMainThread)
            }
        })
        let recoveryStore = disk.store(localFile: localFile)
        let controller = TaskDraftRecoveryController(store: recoveryStore)
        let ticket = try #require(
            controller.makePersistenceTicket(
                dirty,
                for: source.task.id,
                hasUnsavedChanges: true
            )
        )

        await controller.persist(ticket)

        #expect(threadProbe.values == [false])
        #expect(
            try await controller.load(
                for: source.task.id,
                currentDraft: current
            ) == dirty
        )

        controller.flush(
            current,
            for: source.task.id,
            hasUnsavedChanges: false
        )
        #expect(
            try FileManager.default.fileExists(
                atPath: recoveryStore.fileURL(for: source.task.id).path
            ) == false
        )
    }

    @Test
    func controllerPerformsExplicitBackgroundRemovalOffTheMainActor() async throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Background removal")
        var dirty = source.draft()
        dirty.title = "Remove without blocking UI"
        let threadProbe = ThreadProbe()
        let recoveryStore = disk.store(
            localFile: DurableLocalFile(injectFault: { point in
                if point == .afterRemovalBeforeDirectorySync {
                    threadProbe.record(Thread.isMainThread)
                }
            })
        )
        try recoveryStore.save(dirty, for: source.task.id)
        let controller = TaskDraftRecoveryController(store: recoveryStore)

        try await controller.removeInBackground(for: source.task.id)

        #expect(threadProbe.values == [false])
        #expect(
            try FileManager.default.fileExists(
                atPath: recoveryStore.fileURL(for: source.task.id).path
            ) == false
        )
    }

    @Test
    func stalePersistenceTicketCannotReviveAnExplicitlyRemovedDraft() async throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Removed recovery")
        let current = source.draft()
        var stale = current
        stale.title = "Stale queued write"
        let recoveryStore = disk.store()
        try recoveryStore.save(stale, for: source.task.id)
        let controller = TaskDraftRecoveryController(store: recoveryStore)
        let ticket = try #require(
            controller.makePersistenceTicket(
                stale,
                for: source.task.id,
                hasUnsavedChanges: true
            )
        )

        try controller.remove(for: source.task.id)
        await controller.persist(ticket)

        #expect(
            try FileManager.default.fileExists(
                atPath: recoveryStore.fileURL(for: source.task.id).path
            ) == false
        )
    }

    @Test
    func operationGateSkipsASupersededRemovalRevision() {
        let gate = TaskDraftRecoveryOperationGate()
        let taskID = UUID()
        let removalRevision = gate.issueRevision(for: taskID)
        _ = gate.issueRevision(for: taskID)
        var didRunRemoval = false

        let didRemove = gate.performIfCurrent(
            sourceTaskID: taskID,
            revision: removalRevision
        ) {
            didRunRemoval = true
        }

        #expect(didRemove == false)
        #expect(didRunRemoval == false)
    }

    @Test
    func removalSupersededDuringIOReportsFailureAndPreservesTheNewRevision() async throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Concurrent recovery")
        let current = source.draft()
        var oldDraft = current
        oldDraft.title = "Old recovery"
        var newDraft = current
        newDraft.title = "New recovery"
        let barrier = RecoveryOperationBarrier()
        let recoveryStore = disk.store(
            localFile: DurableLocalFile(injectFault: { point in
                if point == .afterRemovalBeforeDirectorySync {
                    barrier.block()
                }
            })
        )
        try recoveryStore.save(oldDraft, for: source.task.id)
        let controller = TaskDraftRecoveryController(store: recoveryStore)
        let sourceTaskID = source.task.id
        let removal = Task.detached {
            do {
                try await controller.removeInBackground(
                    for: sourceTaskID
                )
                return false
            } catch let error as TaskDraftRecoveryControllerError {
                return error == .removalSuperseded
            } catch {
                return false
            }
        }

        await barrier.waitUntilBlocked()
        let newTicket = try #require(
            controller.makePersistenceTicket(
                newDraft,
                for: sourceTaskID,
                hasUnsavedChanges: true
            )
        )
        let persistence = Task.detached {
            await controller.persist(newTicket)
        }
        barrier.release()

        #expect(await removal.value)
        await persistence.value
        #expect(
            try await controller.load(
                for: sourceTaskID,
                currentDraft: current
            ) == newDraft
        )
    }

    @Test
    func explicitRemovalFailurePropagatesAndStillInvalidatesStaleTickets() async throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Removal failure")
        let current = source.draft()
        var stale = current
        stale.title = "Must not return"
        let localFile = DurableLocalFile(injectFault: { point in
            if point == .afterRemovalBeforeDirectorySync {
                throw InjectedRemovalFailure()
            }
        })
        let recoveryStore = disk.store(localFile: localFile)
        try recoveryStore.save(stale, for: source.task.id)
        let controller = TaskDraftRecoveryController(store: recoveryStore)
        let ticket = try #require(
            controller.makePersistenceTicket(
                stale,
                for: source.task.id,
                hasUnsavedChanges: true
            )
        )

        #expect(throws: InjectedRemovalFailure.self) {
            try controller.remove(for: source.task.id)
        }
        await controller.persist(ticket)

        #expect(
            try FileManager.default.fileExists(
                atPath: recoveryStore.fileURL(for: source.task.id).path
            ) == false
        )
    }

    @Test
    func retryAfterInterruptedRemovalReplaysDirectorySynchronization() throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Removal retry")
        var dirty = source.draft()
        dirty.title = "Durably discard me"
        let failingFile = DurableLocalFile(injectFault: { point in
            if point == .afterRemovalBeforeDirectorySync {
                throw InjectedRemovalFailure()
            }
        })
        let failingStore = disk.store(localFile: failingFile)
        try failingStore.save(dirty, for: source.task.id)

        #expect(throws: InjectedRemovalFailure.self) {
            try failingStore.remove(for: source.task.id)
        }
        #expect(
            try FileManager.default.fileExists(
                atPath: failingStore.fileURL(for: source.task.id).path
            ) == false
        )

        let syncProbe = RemovalDirectorySyncProbe()
        let retryStore = disk.store(
            localFile: DurableLocalFile(
                directorySynchronizer: syncProbe.synchronize
            )
        )
        try retryStore.remove(for: source.task.id)

        #expect(
            syncProbe.paths.contains(
                CanonicalFileURL.resolvingExistingAncestor(
                    of: disk.directory
                )
            )
        )
    }

    @Test
    func stalePersistenceTicketCannotOverwriteANewerFlush() async throws {
        let disk = try DiskFixture()
        defer { disk.remove() }
        let source = ExistingTaskFixture(title: "Newer flush")
        let current = source.draft()
        var stale = current
        stale.title = "Stale queued write"
        var newer = current
        newer.title = "Newest lifecycle flush"
        let recoveryStore = disk.store()
        let controller = TaskDraftRecoveryController(store: recoveryStore)
        let ticket = try #require(
            controller.makePersistenceTicket(
                stale,
                for: source.task.id,
                hasUnsavedChanges: true
            )
        )

        controller.flush(
            newer,
            for: source.task.id,
            hasUnsavedChanges: true
        )
        await controller.persist(ticket)

        #expect(
            try recoveryStore.load(
                for: source.task.id,
                currentDraft: current
            ) == newer
        )
    }

    @Test
    func uiTestingDefaultDirectoryIsStableAndProcessIsolated() throws {
        let taskID = UUID()
        let first = TaskDraftRecoveryStore(
            commandLineArguments: ["timetracker", "--uitesting"],
            processIdentifier: 42
        )
        let second = TaskDraftRecoveryStore(
            commandLineArguments: ["timetracker", "--uitesting"],
            processIdentifier: 43
        )

        #expect(
            try first.fileURL(for: taskID)
                .deletingLastPathComponent().lastPathComponent ==
                "TimeTrackerDrafts-42"
        )
        #expect(
            try first.fileURL(for: taskID)
                .deletingLastPathComponent() !=
                second.fileURL(for: taskID).deletingLastPathComponent()
        )
    }

    @MainActor
    private struct ExistingTaskFixture {
        let task: TaskNode
        let checklistItem: ChecklistItem
        let visual: ChecklistItemVisual

        init(title: String) {
            task = TaskNode(
                title: title,
                parentID: nil,
                deviceID: "draft-recovery-tests",
                colorHex: "1677FF",
                iconName: "checkmark.circle"
            )
            task.notes = "Persisted notes"
            task.estimatedSeconds = 25 * 60
            task.dueAt = Date(timeIntervalSince1970: 50000)
            checklistItem = ChecklistItem(
                taskID: task.id,
                title: "Persisted checklist item",
                deviceID: "draft-recovery-tests"
            )
            visual = ChecklistItemVisual(
                checklistItemID: checklistItem.id,
                iconName: "book",
                colorHex: "34C759",
                deviceID: "draft-recovery-tests"
            )
        }

        func draft() -> TaskEditorDraft {
            TaskEditorDraft(
                task: task,
                checklistItems: [checklistItem],
                visualByChecklistID: [checklistItem.id: visual]
            )
        }
    }

    @MainActor
    private struct DiskFixture {
        let root: URL
        let directory: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "TaskDraftRecoveryStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
            directory = root.appendingPathComponent(
                TaskDraftRecoveryStore.directoryName,
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        func store(
            now: Date = Date(timeIntervalSince1970: 30000),
            retentionInterval: TimeInterval = 3600,
            maximumEncodedByteCount: Int =
                TaskDraftRecoveryStore.maximumEncodedByteCount,
            localFile: DurableLocalFile? = nil
        ) -> TaskDraftRecoveryStore {
            TaskDraftRecoveryStore(
                directoryURL: directory,
                durableRootURL: root,
                retentionInterval: retentionInterval,
                maximumEncodedByteCount: maximumEncodedByteCount,
                now: { now },
                localFile: localFile
            )
        }

        func writeEnvelope(
            _ envelope: TaskDraftRecoveryEnvelope,
            fileNameTaskID: UUID
        ) throws -> URL {
            try write(
                TaskDraftRecoveryCodec.encode(envelope),
                fileNameTaskID: fileNameTaskID
            )
        }

        func write(
            _ data: Data,
            fileNameTaskID: UUID
        ) throws -> URL {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let url = try store().fileURL(for: fileNameTaskID)
            try data.write(to: url)
            return url
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private struct InjectedReadFailure: Error {}
    private struct InjectedRemovalFailure: Error {}

    private final class RemovalDirectorySyncProbe {
        private(set) var paths: [URL] = []

        func synchronize(_ url: URL) {
            paths.append(url)
        }
    }

    private final nonisolated class ThreadProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var recordedValues: [Bool] = []

        var values: [Bool] {
            lock.withLock { recordedValues }
        }

        func record(_ value: Bool) {
            lock.withLock {
                recordedValues.append(value)
            }
        }
    }

    private final nonisolated class RecoveryOperationBarrier:
        @unchecked Sendable
    {
        private let lock = NSLock()
        private let resume = DispatchSemaphore(value: 0)
        private var hasEntered = false
        private var entryWaiters: [CheckedContinuation<Void, Never>] = []

        func block() {
            let waiters = lock.withLock {
                hasEntered = true
                defer { entryWaiters.removeAll() }
                return entryWaiters
            }
            waiters.forEach { $0.resume() }
            resume.wait()
        }

        func waitUntilBlocked() async {
            await withCheckedContinuation { continuation in
                let shouldResume = lock.withLock {
                    guard hasEntered == false else { return true }
                    entryWaiters.append(continuation)
                    return false
                }
                if shouldResume {
                    continuation.resume()
                }
            }
        }

        func release() {
            resume.signal()
        }
    }
}
