import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct InboxPersistencePolicyTests {
    private let localDeviceID = "local-device"
    private let remoteDeviceID = "remote-device"

    @Test @MainActor
    func policyAcceptsExactUTF8BoundariesAndSupportedMultilineWhitespace() throws {
        let exactTitle = String(repeating: "界", count: 1365) + "a"
        let exactMultiline = String(repeating: "界", count: 21844) + "\t\n\ra"
        let exactCompact = String(repeating: "界", count: 85) + "a"

        #expect(exactTitle.utf8.count == SyncDataSnapshotRestoreLimits.maximumTitleByteCount)
        #expect(exactMultiline.utf8.count == SyncDataSnapshotRestoreLimits.maximumNoteByteCount)
        #expect(exactCompact.utf8.count == SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount)

        let item = try InboxPersistencePolicy.prepareItem(
            title: "  \(exactTitle)  ",
            notes: exactMultiline,
            suggestionReason: " \(exactMultiline) "
        )
        let suggestion = try InboxPersistencePolicy.prepareSuggestion(
            reason: exactMultiline,
            iconName: exactCompact,
            colorHex: exactCompact,
            modelID: " \(exactCompact) ",
            titleSnapshot: " \(exactTitle) "
        )

        #expect(item.title == exactTitle)
        #expect(item.notes == exactMultiline)
        #expect(item.suggestionReason == exactMultiline)
        #expect(suggestion.reason == exactMultiline)
        #expect(suggestion.iconName == ChecklistVisualSanitizer.defaultIcon)
        #expect(suggestion.colorHex == ChecklistVisualSanitizer.defaultColor)
        #expect(suggestion.modelID == exactCompact)
        #expect(suggestion.titleSnapshot == exactTitle)
    }

    @Test @MainActor
    func policyRejectsRequiredEmptyOversizedAndUnsupportedControlText() throws {
        let compactMaximum = SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
        let oversizedColor = String(repeating: "c", count: compactMaximum + 1)

        #expect(throws: InboxPersistenceValidationError.required(field: .itemTitle)) {
            try InboxPersistencePolicy.prepareItem(
                title: " \n ",
                notes: nil,
                suggestionReason: nil
            )
        }
        #expect(throws: InboxPersistenceValidationError.controlCharacter(field: .itemTitle)) {
            try InboxPersistencePolicy.prepareItem(
                title: "Unsafe\u{0000}title",
                notes: nil,
                suggestionReason: nil
            )
        }
        #expect(throws: InboxPersistenceValidationError.controlCharacter(field: .notes)) {
            try InboxPersistencePolicy.prepareItem(
                title: "Safe",
                notes: "Unsafe\u{0000}notes",
                suggestionReason: nil
            )
        }
        #expect(throws: InboxPersistenceValidationError.controlCharacter(field: .suggestionReason)) {
            try InboxPersistencePolicy.prepareSuggestion(
                reason: "Unsafe\u{000B}reason",
                iconName: "book",
                colorHex: "1677FF",
                modelID: "model",
                titleSnapshot: "Safe"
            )
        }
        #expect(throws: InboxPersistenceValidationError.controlCharacter(field: .iconName)) {
            try InboxPersistencePolicy.prepareSuggestion(
                reason: nil,
                iconName: "book\nfolder",
                colorHex: "1677FF",
                modelID: "model",
                titleSnapshot: "Safe"
            )
        }
        #expect(throws: InboxPersistenceValidationError.byteLimitExceeded(
            field: .colorHex,
            actual: compactMaximum + 1,
            maximum: compactMaximum
        )) {
            try InboxPersistencePolicy.prepareSuggestion(
                reason: nil,
                iconName: "book",
                colorHex: oversizedColor,
                modelID: "model",
                titleSnapshot: "Safe"
            )
        }
        #expect(throws: InboxPersistenceValidationError.required(field: .titleSnapshot)) {
            try InboxPersistencePolicy.prepareSuggestion(
                reason: nil,
                iconName: "book",
                colorHex: "1677FF",
                modelID: "model",
                titleSnapshot: "  "
            )
        }
    }

    @Test @MainActor
    func captureWritesValidateBeforeInsertionAndKeepBlankCaptureAsNoOp() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let noteMaximum = SyncDataSnapshotRestoreLimits.maximumNoteByteCount
        let oversizedNotes = String(repeating: "界", count: noteMaximum / 3 + 1)

        #expect(try handler.add(
            title: " \n ",
            notes: "Ignored",
            existingItems: [],
            context: context,
            deviceID: localDeviceID
        ) == nil)
        #expect(throws: InboxPersistenceValidationError.controlCharacter(field: .itemTitle)) {
            try handler.add(
                title: "Unsafe\u{0000}capture",
                existingItems: [],
                context: context,
                deviceID: localDeviceID
            )
        }
        #expect(throws: InboxPersistenceValidationError.byteLimitExceeded(
            field: .notes,
            actual: oversizedNotes.utf8.count,
            maximum: noteMaximum
        )) {
            try handler.add(
                title: "Safe capture",
                notes: oversizedNotes,
                existingItems: [],
                context: context,
                deviceID: localDeviceID
            )
        }
        #expect(try context.fetch(FetchDescriptor<InboxItem>()).isEmpty)

        let item = try #require(try handler.add(
            title: "  Safe capture  ",
            notes: "Line one\tvalue\nLine two\rLine three",
            existingItems: [],
            context: context,
            deviceID: localDeviceID
        ))
        #expect(item.title == "Safe capture")
        #expect(item.notes == "Line one\tvalue\nLine two\rLine three")
    }

    @Test @MainActor
    func suggestionUpsertPreflightsEveryTombstoneBeforeChangingAnyRow() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let item = InboxItem(title: "Original item", deviceID: remoteDeviceID)
        item.suggestedTaskID = UUID()
        item.suggestionReason = "Original reason"
        let older = makeSuggestion(item: item, modelID: "remote-model")
        older.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let newer = makeSuggestion(item: item, modelID: "newer-model")
        newer.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        context.insert(item)
        context.insert(older)
        context.insert(newer)
        try context.save()

        let itemUpdatedAt = item.updatedAt
        let itemMutationID = item.clientMutationID
        let oldSuggestedTaskID = item.suggestedTaskID
        let newerTaskID = newer.taskID
        let newerUpdatedAt = newer.updatedAt
        let newerMutationID = newer.clientMutationID
        let compactMaximum = SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
        older.modelID = String(repeating: "m", count: compactMaximum + 1)
        try context.save()
        let olderUpdatedAt = older.updatedAt
        let olderMutationID = older.clientMutationID

        #expect(throws: InboxPersistenceValidationError.byteLimitExceeded(
            field: .modelID,
            actual: compactMaximum + 1,
            maximum: compactMaximum
        )) {
            try handler.upsertSuggestion(
                item: item,
                result: LLMInboxSuggestionResult(
                    destination: .checklist(taskID: UUID()),
                    reason: "Replacement reason",
                    iconName: "book",
                    colorHex: "16A34A",
                    modelID: "replacement-model"
                ),
                context: context,
                now: Date(timeIntervalSinceReferenceDate: 5000),
                deviceID: localDeviceID
            )
        }

        #expect(item.suggestedTaskID == oldSuggestedTaskID)
        #expect(item.suggestionReason == "Original reason")
        #expect(item.updatedAt == itemUpdatedAt)
        #expect(item.clientMutationID == itemMutationID)
        #expect(item.deviceID == remoteDeviceID)
        #expect(newer.taskID == newerTaskID)
        #expect(newer.deletedAt == nil)
        #expect(newer.updatedAt == newerUpdatedAt)
        #expect(newer.clientMutationID == newerMutationID)
        #expect(newer.deviceID == remoteDeviceID)
        #expect(older.deletedAt == nil)
        #expect(older.updatedAt == olderUpdatedAt)
        #expect(older.clientMutationID == olderMutationID)
        #expect(older.deviceID == remoteDeviceID)
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).count == 2)
    }

    @Test @MainActor
    func manualSuggestionDraftRejectsControlsWithoutChangingWriterMetadata() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let item = InboxItem(title: "Manual route", deviceID: remoteDeviceID)
        let suggestion = makeSuggestion(item: item, modelID: "remote-model")
        context.insert(item)
        context.insert(suggestion)
        try context.save()
        let itemUpdatedAt = item.updatedAt
        let itemMutationID = item.clientMutationID
        let suggestionUpdatedAt = suggestion.updatedAt
        let suggestionMutationID = suggestion.clientMutationID

        var draft = InboxSuggestionEditorDraft(item: item, suggestion: suggestion)
        draft.reason = "First line\nSecond line"
        draft.iconName = "book\u{0000}"
        #expect(throws: InboxPersistenceValidationError.controlCharacter(field: .iconName)) {
            try handler.saveSuggestionDraft(
                item: item,
                draft: draft,
                context: context,
                now: Date(timeIntervalSinceReferenceDate: 6000),
                deviceID: localDeviceID
            )
        }

        #expect(item.updatedAt == itemUpdatedAt)
        #expect(item.clientMutationID == itemMutationID)
        #expect(item.deviceID == remoteDeviceID)
        #expect(suggestion.updatedAt == suggestionUpdatedAt)
        #expect(suggestion.clientMutationID == suggestionMutationID)
        #expect(suggestion.deviceID == remoteDeviceID)
    }

    @Test @MainActor
    func applyingSuggestionCopiesOnlyPreparedBoundedText() throws {
        let context = try makeTestContext()
        let exactTitle = String(repeating: "界", count: 1365) + "a"
        let exactModelID = String(repeating: "界", count: 85) + "a"
        let item = InboxItem(title: " \(exactTitle) ", deviceID: remoteDeviceID)
        item.notes = "Line one\tvalue\nLine two\rLine three"
        item.suggestionReason = " First line\nSecond line "
        let suggestion = InboxSuggestion(
            inboxItemID: item.id,
            taskID: UUID(),
            reason: " First line\nSecond line ",
            iconName: "  book  ",
            colorHex: " #16a34a ",
            modelID: " \(exactModelID) ",
            titleSnapshot: " \(exactTitle) ",
            deviceID: remoteDeviceID
        )
        context.insert(item)
        context.insert(suggestion)
        try context.save()

        let checklistItem = try InboxCommandHandler().applySuggestion(
            item: item,
            suggestion: suggestion,
            existingChecklistItems: [],
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 7000),
            deviceID: localDeviceID
        )
        let visual = try #require(
            try context.fetch(FetchDescriptor<ChecklistItemVisual>())
                .first { $0.checklistItemID == checklistItem.id }
        )

        #expect(checklistItem.title == exactTitle)
        #expect(checklistItem.title.utf8.count == SyncDataSnapshotRestoreLimits.maximumTitleByteCount)
        #expect(visual.iconName == "book")
        #expect(visual.colorHex == "16A34A")
        #expect(visual.suggestionTitleSnapshot == exactTitle)
        #expect(visual.suggestionModelID == exactModelID)
        #expect(visual.suggestionModelID?.utf8.count == SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount)
        #expect(item.title == exactTitle)
        #expect(item.suggestionReason == "First line\nSecond line")
        #expect(item.deletedAt == Date(timeIntervalSinceReferenceDate: 7000))
        #expect(suggestion.reason == "First line\nSecond line")
        #expect(suggestion.iconName == "book")
        #expect(suggestion.colorHex == "16A34A")
        #expect(suggestion.modelID == exactModelID)
        #expect(suggestion.titleSnapshot == exactTitle)
        #expect(suggestion.deletedAt == Date(timeIntervalSinceReferenceDate: 7000))
    }

    @Test @MainActor
    func invalidApplyHasNoChecklistOrSourceSideEffects() throws {
        let context = try makeTestContext()
        let item = InboxItem(title: "Keep in inbox", deviceID: remoteDeviceID)
        let compactMaximum = SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
        let suggestion = makeSuggestion(
            item: item,
            modelID: String(repeating: "m", count: compactMaximum + 1)
        )
        context.insert(item)
        context.insert(suggestion)
        try context.save()
        let itemUpdatedAt = item.updatedAt
        let itemMutationID = item.clientMutationID
        let suggestionUpdatedAt = suggestion.updatedAt
        let suggestionMutationID = suggestion.clientMutationID

        #expect(throws: InboxPersistenceValidationError.byteLimitExceeded(
            field: .modelID,
            actual: compactMaximum + 1,
            maximum: compactMaximum
        )) {
            try InboxCommandHandler().applySuggestion(
                item: item,
                suggestion: suggestion,
                existingChecklistItems: [],
                context: context,
                now: Date(timeIntervalSinceReferenceDate: 8000),
                deviceID: localDeviceID
            )
        }

        #expect(item.deletedAt == nil)
        #expect(item.updatedAt == itemUpdatedAt)
        #expect(item.clientMutationID == itemMutationID)
        #expect(item.deviceID == remoteDeviceID)
        #expect(suggestion.deletedAt == nil)
        #expect(suggestion.updatedAt == suggestionUpdatedAt)
        #expect(suggestion.clientMutationID == suggestionMutationID)
        #expect(suggestion.deviceID == remoteDeviceID)
        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
    }

    @Test @MainActor
    func standaloneApplyRollsBackEveryRowWhenFinalSaveFails() throws {
        let directory = try makeStoreDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "inbox.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let itemID = UUID()
        let suggestionID = UUID()
        let originalDate = Date(timeIntervalSinceReferenceDate: 9000)

        try initializeWritableStore(at: storeURL, schema: schema) { context in
            let item = InboxItem(title: "Original inbox item", deviceID: remoteDeviceID)
            item.id = itemID
            item.updatedAt = originalDate
            let suggestion = InboxSuggestion(
                inboxItemID: itemID,
                taskID: UUID(),
                reason: "Original reason",
                iconName: "book",
                colorHex: "16A34A",
                modelID: "remote-model",
                titleSnapshot: item.title,
                deviceID: remoteDeviceID
            )
            suggestion.id = suggestionID
            suggestion.updatedAt = originalDate
            context.insert(item)
            context.insert(suggestion)
        }

        let container = try makeReadOnlyContainer(at: storeURL, schema: schema)
        let context = ModelContext(container)
        let item = try #require(
            try context.fetch(FetchDescriptor<InboxItem>()).first { $0.id == itemID }
        )
        let suggestion = try #require(
            try context.fetch(FetchDescriptor<InboxSuggestion>()).first { $0.id == suggestionID }
        )
        let itemMutationID = item.clientMutationID
        let suggestionMutationID = suggestion.clientMutationID

        do {
            _ = try InboxCommandHandler().applySuggestion(
                item: item,
                suggestion: suggestion,
                existingChecklistItems: [],
                context: context,
                now: Date(timeIntervalSinceReferenceDate: 10000),
                deviceID: localDeviceID
            )
            Issue.record("Expected the read-only store to reject the save")
        } catch let error as InboxPersistenceValidationError {
            Issue.record("Expected a persistence failure, got validation error: \(error)")
        } catch {
            // The concrete SwiftData save error is intentionally not part of the command API.
        }

        let storedItem = try #require(
            try context.fetch(FetchDescriptor<InboxItem>()).first { $0.id == itemID }
        )
        let storedSuggestion = try #require(
            try context.fetch(FetchDescriptor<InboxSuggestion>()).first { $0.id == suggestionID }
        )
        #expect(storedItem.deletedAt == nil)
        #expect(storedItem.updatedAt == originalDate)
        #expect(storedItem.deviceID == remoteDeviceID)
        #expect(storedItem.clientMutationID == itemMutationID)
        #expect(storedSuggestion.deletedAt == nil)
        #expect(storedSuggestion.updatedAt == originalDate)
        #expect(storedSuggestion.deviceID == remoteDeviceID)
        #expect(storedSuggestion.clientMutationID == suggestionMutationID)
        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
    }

    @MainActor
    private func makeSuggestion(item: InboxItem, modelID: String) -> InboxSuggestion {
        InboxSuggestion(
            inboxItemID: item.id,
            taskID: UUID(),
            reason: "Remote reason",
            iconName: "book",
            colorHex: "16A34A",
            modelID: modelID,
            titleSnapshot: item.title,
            deviceID: remoteDeviceID
        )
    }

    @MainActor
    private func initializeWritableStore(
        at url: URL,
        schema: Schema,
        seed: (ModelContext) throws -> Void
    ) throws {
        let configuration = ModelConfiguration(
            "WritableInboxPersistencePolicyTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        try seed(context)
        try context.save()
    }

    @MainActor
    private func makeReadOnlyContainer(at url: URL, schema: Schema) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "ReadOnlyInboxPersistencePolicyTests-\(UUID().uuidString)",
            schema: schema,
            url: url,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func makeStoreDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "InboxPersistencePolicyTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
