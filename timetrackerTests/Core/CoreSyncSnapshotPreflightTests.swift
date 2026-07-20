import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSyncSnapshotPreflightTests {
    @Test @MainActor
    func oversizedTableIsRejectedBeforeExistingRowsChange() throws {
        let (context, sentinelID) = try makeSentinelContext()
        let record = TaskRecord(TaskNode(title: "Repeated", parentID: nil, deviceID: "source"))
        let recordCount = SyncDataSnapshotRestoreLimits.maximumRecordsPerTable + 1
        let snapshot = SyncDataSnapshot(tasks: Array(repeating: record, count: recordCount))

        #expect(throws: SyncDataSnapshotPreflightError.tableRecordLimitExceeded(
            table: .tasks,
            actual: recordCount,
            maximum: SyncDataSnapshotRestoreLimits.maximumRecordsPerTable
        )) {
            try snapshot.restoreAsLocalWinner(context: context)
        }
        try expectSentinelUnchanged(context: context, id: sentinelID)
    }

    @Test @MainActor
    func duplicateIdentifierIsRejectedBeforeExistingRowsChange() throws {
        let (context, sentinelID) = try makeSentinelContext()
        let record = TaskRecord(TaskNode(title: "Duplicate", parentID: nil, deviceID: "source"))
        let snapshot = SyncDataSnapshot(tasks: [record, record])

        #expect(throws: SyncDataSnapshotPreflightError.duplicateIdentifier(table: .tasks, id: record.id)) {
            try snapshot.restoreAsLocalWinner(context: context)
        }
        try expectSentinelUnchanged(context: context, id: sentinelID)
    }

    @Test @MainActor
    func oversizedTextIsRejectedBeforeExistingRowsChange() throws {
        let (context, sentinelID) = try makeSentinelContext()
        let task = TaskNode(
            title: String(repeating: "a", count: SyncDataSnapshotRestoreLimits.maximumTitleByteCount + 1),
            parentID: nil,
            deviceID: "source"
        )
        let record = TaskRecord(task)
        let snapshot = SyncDataSnapshot(tasks: [record])

        #expect(throws: SyncDataSnapshotPreflightError.fieldByteLimitExceeded(
            table: .tasks,
            id: record.id,
            field: "title",
            actual: SyncDataSnapshotRestoreLimits.maximumTitleByteCount + 1,
            maximum: SyncDataSnapshotRestoreLimits.maximumTitleByteCount
        )) {
            try snapshot.restoreAsLocalWinner(context: context)
        }
        try expectSentinelUnchanged(context: context, id: sentinelID)
    }

    @Test @MainActor
    func invalidEnumAndNonFiniteSortOrderAreRejected() throws {
        let invalidStatusContext = try makeSentinelContext()
        let invalidStatusTask = TaskNode(title: "Invalid status", parentID: nil, deviceID: "source")
        invalidStatusTask.statusRaw = "future-status"
        let invalidStatusRecord = TaskRecord(invalidStatusTask)

        #expect(throws: SyncDataSnapshotPreflightError.invalidRawValue(
            table: .tasks,
            id: invalidStatusRecord.id,
            field: "statusRaw",
            value: "future-status"
        )) {
            try SyncDataSnapshot(tasks: [invalidStatusRecord])
                .restoreAsLocalWinner(context: invalidStatusContext.0)
        }
        try expectSentinelUnchanged(context: invalidStatusContext.0, id: invalidStatusContext.1)

        let nonFiniteContext = try makeSentinelContext()
        let nonFiniteTask = TaskNode(title: "Invalid order", parentID: nil, deviceID: "source")
        nonFiniteTask.sortOrder = .infinity
        let nonFiniteRecord = TaskRecord(nonFiniteTask)

        #expect(throws: SyncDataSnapshotPreflightError.nonFiniteNumber(
            table: .tasks,
            id: nonFiniteRecord.id,
            field: "sortOrder"
        )) {
            try SyncDataSnapshot(tasks: [nonFiniteRecord])
                .restoreAsLocalWinner(context: nonFiniteContext.0)
        }
        try expectSentinelUnchanged(context: nonFiniteContext.0, id: nonFiniteContext.1)
    }

    @Test @MainActor
    func invalidInboxSuggestionDestinationKindIsRejectedBeforeExistingRowsChange() throws {
        let (context, sentinelID) = try makeSentinelContext()
        let invalidRawValue = "future-destination"
        let suggestion = InboxSuggestion(
            inboxItemID: UUID(),
            taskID: UUID(),
            titleSnapshot: "Invalid destination",
            deviceID: "source"
        )
        suggestion.destinationKindRaw = invalidRawValue
        let record = InboxSuggestionRecord(suggestion)

        #expect(throws: SyncDataSnapshotPreflightError.invalidRawValue(
            table: .inboxSuggestions,
            id: record.id,
            field: "destinationKindRaw",
            value: invalidRawValue
        )) {
            try SyncDataSnapshot(inboxSuggestions: [record])
                .restoreAsLocalWinner(context: context)
        }
        try expectSentinelUnchanged(context: context, id: sentinelID)
    }

    @Test @MainActor
    func oversizedInboxSuggestionDestinationKindIsRejectedBeforeExistingRowsChange() throws {
        let (context, sentinelID) = try makeSentinelContext()
        let oversizedRawValue = String(
            repeating: "a",
            count: SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount + 1
        )
        let suggestion = InboxSuggestion(
            inboxItemID: UUID(),
            taskID: UUID(),
            titleSnapshot: "Oversized destination",
            deviceID: "source"
        )
        suggestion.destinationKindRaw = oversizedRawValue
        let record = InboxSuggestionRecord(suggestion)

        #expect(throws: SyncDataSnapshotPreflightError.fieldByteLimitExceeded(
            table: .inboxSuggestions,
            id: record.id,
            field: "destinationKindRaw",
            actual: SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount + 1,
            maximum: SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
        )) {
            try SyncDataSnapshot(inboxSuggestions: [record])
                .restoreAsLocalWinner(context: context)
        }
        try expectSentinelUnchanged(context: context, id: sentinelID)
    }

    @Test @MainActor
    func legacyTaskStatusRawValuesPassPreflightAndRestoreVerbatim() throws {
        let context = try makeTestContext()
        let rawValues = [
            LegacyTaskStatusRaw.active,
            LegacyTaskStatusRaw.planned,
            LegacyTaskStatusRaw.completed,
            LegacyTaskStatusRaw.archived,
        ]
        let sourceTasks = rawValues.map { rawValue in
            let task = TaskNode(
                title: "Legacy \(rawValue)",
                parentID: nil,
                deviceID: "source"
            )
            task.statusRaw = rawValue
            task.archivedAt = nil
            return task
        }
        let archivedAt = Date(timeIntervalSinceReferenceDate: 123)
        sourceTasks[0].archivedAt = archivedAt
        let snapshot = SyncDataSnapshot(tasks: sourceTasks.map(TaskRecord.init))

        #expect(Set(rawValues) == LegacyTaskStatusRaw.acceptedValues)
        try snapshot.validateForRestore()
        try snapshot.restoreAsLocalWinner(context: context)

        let restoredByRaw = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskNode>())
                .map { ($0.statusRaw, $0) }
        )
        #expect(Set(restoredByRaw.keys) == LegacyTaskStatusRaw.acceptedValues)
        let active = try #require(restoredByRaw[LegacyTaskStatusRaw.active])
        #expect(active.statusRaw == LegacyTaskStatusRaw.active)
        #expect(active.archivedAt == archivedAt)
        #expect(active.isArchivedForLifecycle)
        let planned = try #require(restoredByRaw[LegacyTaskStatusRaw.planned])
        let completed = try #require(restoredByRaw[LegacyTaskStatusRaw.completed])
        #expect(planned.statusRaw == LegacyTaskStatusRaw.planned)
        #expect(planned.isArchivedForLifecycle == false)
        #expect(completed.statusRaw == LegacyTaskStatusRaw.completed)
        #expect(completed.isArchivedForLifecycle == false)
        let archived = try #require(restoredByRaw[LegacyTaskStatusRaw.archived])
        #expect(archived.statusRaw == LegacyTaskStatusRaw.archived)
        #expect(archived.archivedAt == nil)
        #expect(archived.isArchivedForLifecycle)

        let eligibility = TaskTrackingAvailabilityService().eligibility(
            tasks: Array(restoredByRaw.values)
        )
        #expect(eligibility.trackableTaskIDs.contains(planned.id))
        #expect(eligibility.trackableTaskIDs.contains(completed.id))
        #expect(eligibility.trackableTaskIDs.contains(active.id) == false)
        #expect(eligibility.trackableTaskIDs.contains(archived.id) == false)
    }

    @Test @MainActor
    func invalidDateAndKnownPreferenceTypeAreRejected() throws {
        let invalidDateContext = try makeSentinelContext()
        let invalidDateTask = TaskNode(title: "Invalid date", parentID: nil, deviceID: "source")
        invalidDateTask.createdAt = Date(timeIntervalSinceReferenceDate: .nan)
        let invalidDateRecord = TaskRecord(invalidDateTask)

        #expect(throws: SyncDataSnapshotPreflightError.invalidDate(
            table: .tasks,
            id: invalidDateRecord.id,
            field: "createdAt"
        )) {
            try SyncDataSnapshot(tasks: [invalidDateRecord])
                .restoreAsLocalWinner(context: invalidDateContext.0)
        }
        try expectSentinelUnchanged(context: invalidDateContext.0, id: invalidDateContext.1)

        let preferenceContext = try makeSentinelContext()
        let preference = SyncedPreference(
            key: AppPreferenceKey.defaultFocusMinutes.rawValue,
            valueJSON: PreferenceJSON.encode("not-an-integer"),
            deviceID: "source"
        )
        let preferenceRecord = SyncedPreferenceRecord(preference)

        #expect(throws: SyncDataSnapshotPreflightError.invalidPreferenceValue(
            id: preferenceRecord.id,
            key: AppPreferenceKey.defaultFocusMinutes.rawValue
        )) {
            try SyncDataSnapshot(syncedPreferences: [preferenceRecord])
                .restoreAsLocalWinner(context: preferenceContext.0)
        }
        try expectSentinelUnchanged(context: preferenceContext.0, id: preferenceContext.1)
    }

    @Test @MainActor
    func invalidTaskPlanInstructionsAreRejectedBeforeExistingRowsChange() throws {
        let (context, sentinelID) = try makeSentinelContext()
        let preference = SyncedPreference(
            key: AppPreferenceKey.llmTaskPlanInstructions.rawValue,
            valueJSON: PreferenceJSON.encode("Plan\u{0000}tasks"),
            deviceID: "source"
        )
        let preferenceRecord = SyncedPreferenceRecord(preference)

        #expect(throws: SyncDataSnapshotPreflightError.invalidPreferenceValue(
            id: preferenceRecord.id,
            key: AppPreferenceKey.llmTaskPlanInstructions.rawValue
        )) {
            try SyncDataSnapshot(syncedPreferences: [preferenceRecord])
                .restoreAsLocalWinner(context: context)
        }
        try expectSentinelUnchanged(context: context, id: sentinelID)
    }

    @Test @MainActor
    func extremeSortOrderAndUnsafePreferenceKeysAreRejected() throws {
        let sortOrderContext = try makeSentinelContext()
        let task = TaskNode(title: "Unadvanceable order", parentID: nil, deviceID: "source")
        task.sortOrder = .greatestFiniteMagnitude
        let taskRecord = TaskRecord(task)

        #expect(throws: SyncDataSnapshotPreflightError.sortOrderCannotAdvance(
            table: .tasks,
            id: taskRecord.id,
            field: "sortOrder"
        )) {
            try SyncDataSnapshot(tasks: [taskRecord])
                .restoreAsLocalWinner(context: sortOrderContext.0)
        }
        try expectSentinelUnchanged(context: sortOrderContext.0, id: sortOrderContext.1)

        for unsafeKey in ["", "future\npreference"] {
            let preferenceContext = try makeSentinelContext()
            let preference = SyncedPreference(
                key: unsafeKey,
                valueJSON: PreferenceJSON.encode(true),
                deviceID: "source"
            )
            let preferenceRecord = SyncedPreferenceRecord(preference)

            #expect(throws: SyncDataSnapshotPreflightError.invalidPreferenceKey(
                id: preferenceRecord.id,
                key: unsafeKey
            )) {
                try SyncDataSnapshot(syncedPreferences: [preferenceRecord])
                    .restoreAsLocalWinner(context: preferenceContext.0)
            }
            try expectSentinelUnchanged(context: preferenceContext.0, id: preferenceContext.1)
        }
    }

    @Test @MainActor
    func provableSessionTaskMismatchIsRejectedBeforeExistingRowsChange() throws {
        let (context, sentinelID) = try makeSentinelContext()
        let expectedTaskID = UUID()
        let actualTaskID = UUID()
        let session = TimeSession(taskID: expectedTaskID, source: .timer, deviceID: "source")
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: actualTaskID,
            source: .timer,
            deviceID: "source"
        )
        let sessionRecord = TimeSessionRecord(session)
        let segmentRecord = TimeSegmentRecord(segment)
        let snapshot = SyncDataSnapshot(sessions: [sessionRecord], segments: [segmentRecord])

        #expect(throws: SyncDataSnapshotPreflightError.inconsistentSessionTask(
            table: .segments,
            id: segmentRecord.id,
            sessionID: sessionRecord.id,
            expectedTaskID: expectedTaskID,
            actualTaskID: actualTaskID
        )) {
            try snapshot.restoreAsLocalWinner(context: context)
        }
        try expectSentinelUnchanged(context: context, id: sentinelID)
    }

    @Test @MainActor
    func validSnapshotRestoresAndPreservesBoundedUnknownPreference() throws {
        let (context, sentinelID) = try makeSentinelContext()
        let incomingTask = TaskNode(title: "Incoming task", parentID: nil, deviceID: "source")
        let unknownPreference = SyncedPreference(
            key: "FuturePreferenceV2",
            valueJSON: PreferenceJSON.encode("opaque-but-bounded-future-value"),
            deviceID: "source"
        )
        let snapshot = SyncDataSnapshot(
            tasks: [TaskRecord(incomingTask)],
            syncedPreferences: [SyncedPreferenceRecord(unknownPreference)]
        )

        try snapshot.restoreAsLocalWinner(context: context)

        let tasks = try context.fetch(FetchDescriptor<TaskNode>())
        #expect(tasks.first { $0.id == sentinelID }?.deletedAt != nil)
        #expect(tasks.first { $0.id == incomingTask.id }?.title == "Incoming task")
        #expect(tasks.first { $0.id == incomingTask.id }?.deletedAt == nil)
        let restoredPreference = try #require(
            try context.fetch(FetchDescriptor<SyncedPreference>())
                .first { $0.id == unknownPreference.id }
        )
        #expect(restoredPreference.key == "FuturePreferenceV2")
        #expect(restoredPreference.valueJSON == PreferenceJSON.encode("opaque-but-bounded-future-value"))
        #expect(restoredPreference.deletedAt == nil)
    }

    @Test @MainActor
    func missingRelationshipRowsRemainCompatibleWithStagedImports() throws {
        let context = try makeTestContext()
        let taskID = UUID()
        let missingSessionID = UUID()
        let segment = TimeSegment(
            sessionID: missingSessionID,
            taskID: taskID,
            source: .timer,
            deviceID: "source"
        )
        let run = PomodoroRun(taskID: taskID, deviceID: "source")
        run.sessionID = missingSessionID
        let snapshot = SyncDataSnapshot(
            segments: [TimeSegmentRecord(segment)],
            pomodoroRuns: [PomodoroRunRecord(run)]
        )

        try snapshot.restoreAsLocalWinner(context: context)

        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<PomodoroRun>()).count == 1)
    }

    @Test @MainActor
    func inboxCaptureReceiptRequiresItsReferencedItemAndRestoresWithIt() throws {
        let context = try makeTestContext()
        let item = InboxItem(title: "Captured externally", deviceID: "source")
        let receipt = InboxCaptureReceipt(
            commandKey: "test.integration\u{1F}\(UUID().uuidString.lowercased())",
            payloadFingerprint: String(repeating: "a", count: 64),
            inboxItemID: item.id,
            deviceID: "source"
        )
        let record = InboxCaptureReceiptRecord(receipt)
        let valid = SyncDataSnapshot(
            inboxItems: [InboxItemRecord(item)],
            inboxCaptureReceipts: [record]
        )

        try valid.restoreAsLocalWinner(context: context)
        #expect(try context.fetch(FetchDescriptor<InboxCaptureReceipt>()).map(\.inboxItemID) == [item.id])

        let missingItem = SyncDataSnapshot(inboxCaptureReceipts: [record])
        #expect(throws: SyncDataSnapshotPreflightError.inconsistentInboxCaptureReceipt(
            id: record.id,
            inboxItemID: item.id
        )) {
            try missingItem.validateForRestore()
        }
    }

    @Test @MainActor
    func inboxCaptureReceiptsRejectConflictingExternalCommandResults() {
        let firstItem = InboxItem(title: "First capture", deviceID: "source")
        let secondItem = InboxItem(title: "Second capture", deviceID: "source")
        let commandKey = "test.integration\u{1F}\(UUID().uuidString.lowercased())"
        let firstReceipt = InboxCaptureReceipt(
            commandKey: commandKey,
            payloadFingerprint: String(repeating: "a", count: 64),
            inboxItemID: firstItem.id,
            deviceID: "source"
        )
        let secondReceipt = InboxCaptureReceipt(
            commandKey: commandKey,
            payloadFingerprint: String(repeating: "a", count: 64),
            inboxItemID: secondItem.id,
            deviceID: "other-device"
        )
        let snapshot = SyncDataSnapshot(
            inboxItems: [InboxItemRecord(firstItem), InboxItemRecord(secondItem)],
            inboxCaptureReceipts: [
                InboxCaptureReceiptRecord(firstReceipt),
                InboxCaptureReceiptRecord(secondReceipt)
            ]
        )

        #expect(throws: SyncDataSnapshotPreflightError.inconsistentInboxCaptureCommandKey(
            commandKey: commandKey
        )) {
            try snapshot.validateForRestore()
        }
    }

    @MainActor
    private func makeSentinelContext() throws -> (ModelContext, UUID) {
        let context = try makeTestContext()
        let sentinel = TaskNode(title: "Sentinel", parentID: nil, deviceID: "existing")
        context.insert(sentinel)
        try context.save()
        return (context, sentinel.id)
    }

    @MainActor
    private func expectSentinelUnchanged(context: ModelContext, id: UUID) throws {
        let tasks = try context.fetch(FetchDescriptor<TaskNode>())
        let sentinelRows = tasks.filter { $0.id == id }
        #expect(sentinelRows.count == 1)
        #expect(sentinelRows.first?.title == "Sentinel")
        #expect(sentinelRows.first?.deletedAt == nil)
        #expect(tasks.allSatisfy { $0.deletedAt == nil })
    }
}
