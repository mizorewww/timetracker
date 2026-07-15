import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct InboxMutationIdentityTests {
    private let localDeviceID = "local-device"
    private let remoteDeviceID = "remote-device"

    @Test @MainActor
    func inboxItemMutationPathsRecordTheCallingDevice() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let toggleItem = try #require(
            try handler.add(
                title: "Toggle",
                existingItems: [],
                context: context,
                deviceID: localDeviceID
            )
        )
        #expect(toggleItem.deviceID == localDeviceID)

        toggleItem.deviceID = remoteDeviceID
        try context.save()
        try handler.toggle(
            toggleItem,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 1_000),
            deviceID: localDeviceID
        )
        #expect(toggleItem.deviceID == localDeviceID)

        let editedItem = InboxItem(title: "Before", deviceID: remoteDeviceID)
        let editedSuggestion = makeSuggestion(for: editedItem, deviceID: remoteDeviceID)
        context.insert(editedItem)
        context.insert(editedSuggestion)
        try context.save()
        try handler.updateTitle(
            editedItem,
            title: "After",
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 2_000),
            deviceID: localDeviceID
        )
        #expect(editedItem.deviceID == localDeviceID)
        #expect(editedSuggestion.deletedAt == Date(timeIntervalSinceReferenceDate: 2_000))
        #expect(editedSuggestion.deviceID == localDeviceID)

        let discardedItem = InboxItem(title: "Discard", deviceID: remoteDeviceID)
        let discardedSuggestion = makeSuggestion(for: discardedItem, deviceID: remoteDeviceID)
        context.insert(discardedItem)
        context.insert(discardedSuggestion)
        try context.save()
        try handler.discardSuggestion(
            discardedItem,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 3_000),
            deviceID: localDeviceID
        )
        #expect(discardedItem.deviceID == localDeviceID)
        #expect(discardedSuggestion.deviceID == localDeviceID)

        let deletedItem = InboxItem(title: "Delete", deviceID: remoteDeviceID)
        let deletedSuggestion = makeSuggestion(for: deletedItem, deviceID: remoteDeviceID)
        context.insert(deletedItem)
        context.insert(deletedSuggestion)
        try context.save()
        try handler.softDelete(
            deletedItem,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 4_000),
            deviceID: localDeviceID
        )
        #expect(deletedItem.deviceID == localDeviceID)
        #expect(deletedSuggestion.deviceID == localDeviceID)

        let blankTitleItem = InboxItem(title: "Blank becomes deleted", deviceID: remoteDeviceID)
        context.insert(blankTitleItem)
        try context.save()
        try handler.updateTitle(
            blankTitleItem,
            title: " \n ",
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 5_000),
            deviceID: localDeviceID
        )
        #expect(blankTitleItem.deletedAt == Date(timeIntervalSinceReferenceDate: 5_000))
        #expect(blankTitleItem.deviceID == localDeviceID)
    }

    @Test @MainActor
    func reorderPrevalidatesTheCompleteOpenItemIdentitySet() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let first = InboxItem(title: "First", sortOrder: 10, deviceID: remoteDeviceID)
        let second = InboxItem(title: "Second", sortOrder: 20, deviceID: remoteDeviceID)
        let completed = InboxItem(
            title: "Completed",
            isCompleted: true,
            sortOrder: 5,
            deviceID: remoteDeviceID
        )
        context.insert(first)
        context.insert(second)
        context.insert(completed)
        try context.save()
        let firstMutationID = first.clientMutationID
        let firstUpdatedAt = first.updatedAt

        try handler.reorderOpenItems(
            orderedItemIDs: [first.id, UUID()],
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 6_000),
            deviceID: localDeviceID
        )
        try context.save()
        #expect(first.sortOrder == 10)
        #expect(first.updatedAt == firstUpdatedAt)
        #expect(first.clientMutationID == firstMutationID)
        #expect(first.deviceID == remoteDeviceID)

        try handler.reorderOpenItems(
            orderedItemIDs: [first.id, first.id],
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 7_000),
            deviceID: localDeviceID
        )
        #expect(first.sortOrder == 10)
        #expect(first.updatedAt == firstUpdatedAt)
        #expect(first.clientMutationID == firstMutationID)
        #expect(first.deviceID == remoteDeviceID)

        try handler.reorderOpenItems(
            orderedItemIDs: [second.id, first.id],
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 8_000),
            deviceID: localDeviceID
        )
        #expect(second.sortOrder == 10)
        #expect(first.sortOrder == 20)
        #expect(first.deviceID == localDeviceID)
        #expect(second.deviceID == localDeviceID)
        #expect(completed.sortOrder == 5)
        #expect(completed.deviceID == remoteDeviceID)
    }

    @Test @MainActor
    func reorderTombstonesActiveLogicalSiblings() throws {
        let context = try makeTestContext()
        let contextID = UUID()
        let revisionID = UUID()
        let staleSibling = InboxItem(title: "First", sortOrder: 30, deviceID: remoteDeviceID)
        staleSibling.suggestionContextID = contextID
        staleSibling.suggestionRevisionID = revisionID
        staleSibling.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let first = InboxItem(title: "First", sortOrder: 10, deviceID: remoteDeviceID)
        first.suggestionContextID = contextID
        first.suggestionRevisionID = revisionID
        first.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        let sameIdentifierSibling = InboxItem(
            title: first.title,
            sortOrder: 40,
            deviceID: remoteDeviceID
        )
        sameIdentifierSibling.id = first.id
        sameIdentifierSibling.suggestionContextID = contextID
        sameIdentifierSibling.suggestionRevisionID = revisionID
        sameIdentifierSibling.updatedAt = Date(timeIntervalSinceReferenceDate: 150)
        let second = InboxItem(title: "Second", sortOrder: 20, deviceID: remoteDeviceID)
        second.updatedAt = Date(timeIntervalSinceReferenceDate: 300)
        context.insert(staleSibling)
        context.insert(first)
        context.insert(sameIdentifierSibling)
        context.insert(second)
        try context.save()

        let reorderedAt = Date(timeIntervalSinceReferenceDate: 9_000)
        try InboxCommandHandler().reorderOpenItems(
            orderedItemIDs: [second.id, first.id],
            context: context,
            now: reorderedAt,
            deviceID: localDeviceID
        )

        #expect(second.sortOrder == 10)
        #expect(first.sortOrder == 20)
        #expect(staleSibling.deletedAt == reorderedAt.addingTimeInterval(-1))
        #expect(staleSibling.updatedAt == reorderedAt.addingTimeInterval(-1))
        #expect(staleSibling.deviceID == localDeviceID)
        #expect(sameIdentifierSibling.deletedAt == reorderedAt.addingTimeInterval(-1))
        #expect(sameIdentifierSibling.updatedAt == reorderedAt.addingTimeInterval(-1))
        #expect(sameIdentifierSibling.deviceID == localDeviceID)
        var store = InboxStore()
        store.refresh(
            items: try context.fetch(FetchDescriptor<InboxItem>()),
            suggestions: []
        )
        #expect(store.items.map(\.id) == [second.id, first.id])
    }

    @Test @MainActor
    func invalidReorderDoesNotMaterializeMergedDismissal() throws {
        let context = try makeTestContext()
        let contextID = UUID()
        let revisionID = UUID()
        let dismissed = InboxItem(title: "First", sortOrder: 10, deviceID: remoteDeviceID)
        dismissed.suggestionContextID = contextID
        dismissed.suggestionRevisionID = revisionID
        dismissed.dismissedSuggestionRevisionID = revisionID
        dismissed.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let newer = InboxItem(title: dismissed.title, sortOrder: 20, deviceID: remoteDeviceID)
        newer.suggestionContextID = contextID
        newer.suggestionRevisionID = revisionID
        newer.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        let second = InboxItem(title: "Second", sortOrder: 30, deviceID: remoteDeviceID)
        second.updatedAt = Date(timeIntervalSinceReferenceDate: 300)
        context.insert(dismissed)
        context.insert(newer)
        context.insert(second)
        try context.save()
        let newerUpdatedAt = newer.updatedAt
        let newerMutationID = newer.clientMutationID

        try InboxCommandHandler().reorderOpenItems(
            orderedItemIDs: [newer.id, UUID()],
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 9_500),
            deviceID: localDeviceID
        )

        #expect(newer.dismissedSuggestionRevisionID == nil)
        #expect(newer.updatedAt == newerUpdatedAt)
        #expect(newer.clientMutationID == newerMutationID)
        #expect(newer.deviceID == remoteDeviceID)
        #expect(dismissed.deletedAt == nil)
        #expect(second.deletedAt == nil)
    }

    @Test @MainActor
    func suggestionUpsertAndDraftPathsRecordTheCallingDevice() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let item = InboxItem(title: "Route this", deviceID: remoteDeviceID)
        let older = makeSuggestion(for: item, deviceID: remoteDeviceID)
        older.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let newer = makeSuggestion(for: item, deviceID: remoteDeviceID)
        newer.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        context.insert(item)
        context.insert(older)
        context.insert(newer)
        try context.save()

        let replacementTaskID = UUID()
        try handler.upsertSuggestion(
            item: item,
            result: LLMInboxSuggestionResult(
                taskID: replacementTaskID,
                reason: "Updated route",
                iconName: "folder",
                colorHex: "16A34A",
                modelID: "test-model"
            ),
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 9_000),
            deviceID: localDeviceID
        )

        #expect(item.deviceID == localDeviceID)
        #expect(newer.taskID == replacementTaskID)
        #expect(newer.deletedAt == nil)
        #expect(newer.deviceID == localDeviceID)
        #expect(older.deletedAt == Date(timeIntervalSinceReferenceDate: 9_000))
        #expect(older.deviceID == localDeviceID)

        item.deviceID = remoteDeviceID
        newer.deviceID = remoteDeviceID
        try context.save()
        var draft = InboxSuggestionEditorDraft(item: item, suggestion: newer)
        draft.reason = "Manual route"
        draft.iconName = "book"
        draft.colorHex = "EF4444"
        try handler.saveSuggestionDraft(
            item: item,
            draft: draft,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 10_000),
            deviceID: localDeviceID
        )
        #expect(item.deviceID == localDeviceID)
        #expect(newer.deviceID == localDeviceID)
        #expect(newer.modelID == "manual")

        let newItem = InboxItem(title: "No suggestion yet", deviceID: remoteDeviceID)
        context.insert(newItem)
        try context.save()
        try handler.upsertSuggestion(
            item: newItem,
            result: LLMInboxSuggestionResult(
                taskID: UUID(),
                reason: "New route",
                iconName: "tray",
                colorHex: "1677FF",
                modelID: "test-model"
            ),
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 11_000),
            deviceID: localDeviceID
        )
        let insertedSuggestion = try #require(
            try context.fetch(FetchDescriptor<InboxSuggestion>())
                .first { $0.inboxItemID == newItem.id && $0.deletedAt == nil }
        )
        #expect(newItem.deviceID == localDeviceID)
        #expect(insertedSuggestion.deviceID == localDeviceID)
    }

    @Test @MainActor
    func applyingSuggestionRecordsTheCallingDeviceAcrossEveryCreatedAndTombstonedRow() throws {
        let context = try makeTestContext()
        let item = InboxItem(title: "Apply me", deviceID: remoteDeviceID)
        let suggestion = makeSuggestion(for: item, deviceID: remoteDeviceID)
        context.insert(item)
        context.insert(suggestion)
        try context.save()

        let checklistItem = try InboxCommandHandler().applySuggestion(
            item: item,
            suggestion: suggestion,
            existingChecklistItems: [],
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 12_000),
            deviceID: localDeviceID
        )
        let visual = try #require(
            try context.fetch(FetchDescriptor<ChecklistItemVisual>())
                .first { $0.checklistItemID == checklistItem.id }
        )

        #expect(item.deletedAt == Date(timeIntervalSinceReferenceDate: 12_000))
        #expect(item.deviceID == localDeviceID)
        #expect(suggestion.deletedAt == Date(timeIntervalSinceReferenceDate: 12_000))
        #expect(suggestion.deviceID == localDeviceID)
        #expect(checklistItem.deviceID == localDeviceID)
        #expect(visual.deviceID == localDeviceID)
    }

    @Test @MainActor
    func noOpAndFailedMutationsPreserveRemoteWriterMetadata() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let item = InboxItem(title: "Unchanged", deviceID: remoteDeviceID)
        let suggestion = makeSuggestion(for: item, deviceID: remoteDeviceID)
        context.insert(item)
        context.insert(suggestion)
        try context.save()
        let originalItemDate = item.updatedAt
        let originalItemMutationID = item.clientMutationID
        let originalSuggestionDate = suggestion.updatedAt
        let originalSuggestionMutationID = suggestion.clientMutationID

        try handler.updateTitle(
            item,
            title: "  Unchanged  ",
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 13_000),
            deviceID: localDeviceID
        )
        #expect(item.deviceID == remoteDeviceID)
        #expect(item.updatedAt == originalItemDate)
        #expect(item.clientMutationID == originalItemMutationID)
        #expect(suggestion.deviceID == remoteDeviceID)

        var invalidDraft = InboxSuggestionEditorDraft(item: item)
        invalidDraft.taskID = nil
        try handler.saveSuggestionDraft(
            item: item,
            draft: invalidDraft,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 14_000),
            deviceID: localDeviceID
        )
        #expect(item.deviceID == remoteDeviceID)
        #expect(item.updatedAt == originalItemDate)
        #expect(item.clientMutationID == originalItemMutationID)

        #expect(throws: ForcedInboxMutationFailure.self) {
            try context.performAtomicMutation {
                try handler.updateTitle(
                    item,
                    title: "Must roll back",
                    context: context,
                    now: Date(timeIntervalSinceReferenceDate: 15_000),
                    deviceID: localDeviceID
                )
                throw ForcedInboxMutationFailure.expected
            }
        }

        let persistedItem = try #require(
            try context.fetch(FetchDescriptor<InboxItem>()).first { $0.id == item.id }
        )
        let persistedSuggestion = try #require(
            try context.fetch(FetchDescriptor<InboxSuggestion>()).first { $0.id == suggestion.id }
        )
        #expect(persistedItem.title == "Unchanged")
        #expect(persistedItem.deviceID == remoteDeviceID)
        #expect(persistedItem.updatedAt == originalItemDate)
        #expect(persistedItem.clientMutationID == originalItemMutationID)
        #expect(persistedSuggestion.deletedAt == nil)
        #expect(persistedSuggestion.deviceID == remoteDeviceID)
        #expect(persistedSuggestion.updatedAt == originalSuggestionDate)
        #expect(persistedSuggestion.clientMutationID == originalSuggestionMutationID)
    }

    @MainActor
    private func makeSuggestion(for item: InboxItem, deviceID: String) -> InboxSuggestion {
        InboxSuggestion(
            inboxItemID: item.id,
            taskID: UUID(),
            reason: "Remote suggestion",
            iconName: "tray",
            colorHex: "1677FF",
            modelID: "remote-model",
            titleSnapshot: item.title,
            deviceID: deviceID
        )
    }
}

private enum ForcedInboxMutationFailure: Error {
    case expected
}
