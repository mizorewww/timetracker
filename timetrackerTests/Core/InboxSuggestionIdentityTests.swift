import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct InboxSuggestionIdentityTests {
    @Test @MainActor
    func dismissalSurvivesSameIdentifierCloudDuplicate() throws {
        let sharedID = UUID()
        let contextID = UUID()
        let revisionID = UUID()
        let dismissed = InboxItem(title: "Dismiss once", deviceID: "older-device")
        dismissed.id = sharedID
        dismissed.suggestionContextID = contextID
        dismissed.suggestionRevisionID = revisionID
        dismissed.dismissedSuggestionRevisionID = revisionID
        dismissed.notes = "Old notes"
        dismissed.sortOrder = 10
        dismissed.updatedAt = Date(timeIntervalSinceReferenceDate: 100)

        let activeDuplicate = InboxItem(title: dismissed.title, deviceID: "newer-device")
        activeDuplicate.id = sharedID
        activeDuplicate.suggestionContextID = contextID
        activeDuplicate.suggestionRevisionID = revisionID
        activeDuplicate.notes = "New notes"
        activeDuplicate.isCompleted = true
        activeDuplicate.completedAt = Date(timeIntervalSinceReferenceDate: 190)
        activeDuplicate.sortOrder = 40
        activeDuplicate.updatedAt = Date(timeIntervalSinceReferenceDate: 200)

        var store = InboxStore()
        store.refresh(items: [dismissed, activeDuplicate], suggestions: [])
        let readModel = try #require(store.itemReadModels.first)
        let winner = readModel.item

        #expect(winner === activeDuplicate)
        #expect(winner.dismissedSuggestionRevisionID == nil)
        #expect(readModel.isCurrentSuggestionRevisionDismissed)
        #expect(winner.notes == "New notes")
        #expect(winner.isCompleted)
        #expect(winner.completedAt == Date(timeIntervalSinceReferenceDate: 190))
        #expect(winner.sortOrder == 40)
    }

    @Test @MainActor
    func dismissedRevisionWinsAcrossPhysicalRowsWithoutConflatingEqualTitles() throws {
        let original = InboxItem(title: "Plan review", deviceID: "device-a")
        let revisionID = original.effectiveSuggestionRevisionID
        original.dismissedSuggestionRevisionID = revisionID
        original.suggestionGeneratedAt = Date(timeIntervalSinceReferenceDate: 100)
        original.updatedAt = Date(timeIntervalSinceReferenceDate: 100)

        let rebuilt = InboxItem(title: original.title, deviceID: "device-b")
        rebuilt.suggestionContextID = original.effectiveSuggestionContextID
        rebuilt.suggestionRevisionID = revisionID
        rebuilt.notes = "New notes"
        rebuilt.sortOrder = 40
        rebuilt.updatedAt = Date(timeIntervalSinceReferenceDate: 200)

        let unrelated = InboxItem(title: original.title, deviceID: "device-c")
        unrelated.updatedAt = Date(timeIntervalSinceReferenceDate: 300)

        var store = InboxStore()
        store.refresh(items: [original, rebuilt, unrelated], suggestions: [])
        #expect(store.items.count == 2)
        let mergedReadModel = try #require(
            store.itemReadModels.first {
                $0.item.effectiveSuggestionContextID == original.effectiveSuggestionContextID
            }
        )
        let merged = mergedReadModel.item
        #expect(merged.id == rebuilt.id)
        #expect(merged.dismissedSuggestionRevisionID == nil)
        #expect(mergedReadModel.isCurrentSuggestionRevisionDismissed)
        #expect(merged.notes == "New notes")
        #expect(merged.sortOrder == 40)
        #expect(
            InboxSuggestionStateService().state(
                for: mergedReadModel,
                suggestion: nil,
                isInFlight: false
            ) == .dismissed
        )
        #expect(original.effectiveSuggestionContextID != unrelated.effectiveSuggestionContextID)
    }

    @Test @MainActor
    func dismissalDoesNotCrossSuggestionRevisions() throws {
        let contextID = UUID()
        let dismissedRevisionID = UUID()
        let dismissed = InboxItem(title: "Old title", deviceID: "old")
        dismissed.suggestionContextID = contextID
        dismissed.suggestionRevisionID = dismissedRevisionID
        dismissed.dismissedSuggestionRevisionID = dismissedRevisionID
        dismissed.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let edited = InboxItem(title: "New title", deviceID: "new")
        edited.suggestionContextID = contextID
        edited.suggestionRevisionID = UUID()
        edited.updatedAt = Date(timeIntervalSinceReferenceDate: 200)

        var store = InboxStore()
        store.refresh(items: [dismissed, edited], suggestions: [])
        let winner = try #require(store.items.first)

        #expect(winner === edited)
        #expect(winner.dismissedSuggestionRevisionID == nil)
        #expect(winner.isCurrentSuggestionRevisionDismissed == false)
    }

    @Test @MainActor
    func facadeRefreshProjectsMergedDismissalWithoutDirtyingSwiftData() throws {
        let context = try makeTestContext()
        let contextID = UUID()
        let revisionID = UUID()
        let dismissed = InboxItem(title: "Keep this dismissed", deviceID: "older")
        dismissed.suggestionContextID = contextID
        dismissed.suggestionRevisionID = revisionID
        dismissed.dismissedSuggestionRevisionID = revisionID
        dismissed.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let current = InboxItem(title: dismissed.title, deviceID: "newer")
        current.suggestionContextID = contextID
        current.suggestionRevisionID = revisionID
        current.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        let suggestion = InboxSuggestion(
            inboxItemID: current.id,
            inboxItemContextID: contextID,
            inboxItemRevisionID: revisionID,
            taskID: UUID(),
            titleSnapshot: current.title,
            deviceID: "newer"
        )
        context.insert(dismissed)
        context.insert(current)
        context.insert(suggestion)
        try context.save()
        #expect(context.hasChanges == false)

        let store = makeTestStore()
        store.configureRepositoriesIfNeeded(context: context)
        try store.refresh(plan: StoreRefreshPlan(scopes: [.inbox]))

        let winner = try #require(store.inboxItems.first)
        let readModel = store.inboxItemReadModel(for: winner)
        #expect(winner === current)
        #expect(winner.dismissedSuggestionRevisionID == nil)
        #expect(readModel.dismissedSuggestionRevisionID == revisionID)
        #expect(readModel.isCurrentSuggestionRevisionDismissed)
        #expect(store.inboxSuggestionByItemID[winner.id]?.id == suggestion.id)
        #expect(store.inboxSuggestion(for: winner) == nil)
        #expect(
            InboxSuggestionStateService().state(
                for: readModel,
                suggestion: suggestion,
                isInFlight: false
            ) == .dismissed
        )
        #expect(context.hasChanges == false)
    }

    @Test @MainActor
    func suggestionIndexFollowsLogicalItemWhenPhysicalIDChanges() throws {
        let taskID = UUID()
        let original = InboxItem(title: "Route this", deviceID: "device-a")
        let suggestion = InboxSuggestion(
            inboxItemID: original.id,
            taskID: taskID,
            titleSnapshot: original.title,
            deviceID: "device-a"
        )
        let rebuilt = InboxItem(title: original.title, deviceID: "device-b")
        rebuilt.suggestionContextID = original.effectiveSuggestionContextID
        rebuilt.suggestionRevisionID = original.effectiveSuggestionRevisionID

        let index = InboxSuggestionIdentityService().index(
            items: [rebuilt],
            suggestions: [suggestion]
        )
        let indexed = try #require(index[rebuilt.id])
        #expect(indexed.id == suggestion.id)
        #expect(
            InboxSuggestionStateService().state(
                for: rebuilt,
                suggestion: indexed,
                isInFlight: false
            ) == .ready
        )
    }

    @Test @MainActor
    func discardAndDeleteCoverEveryPhysicalRowInTheLogicalItem() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let task = TaskNode(title: "Study", parentID: nil, deviceID: "test")
        let original = InboxItem(title: "Review notes", deviceID: "device-a")
        let rebuilt = InboxItem(title: original.title, deviceID: "device-b")
        rebuilt.suggestionContextID = original.effectiveSuggestionContextID
        rebuilt.suggestionRevisionID = original.effectiveSuggestionRevisionID
        let originalSuggestion = makeSuggestion(item: original, taskID: task.id)
        let rebuiltSuggestion = makeSuggestion(item: rebuilt, taskID: task.id)
        context.insert(task)
        context.insert(original)
        context.insert(rebuilt)
        context.insert(originalSuggestion)
        context.insert(rebuiltSuggestion)
        try context.save()

        let discardedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        try handler.discardSuggestion(
            rebuilt,
            context: context,
            now: discardedAt,
            deviceID: "local"
        )

        #expect(rebuilt.dismissedSuggestionRevisionID == rebuilt.effectiveSuggestionRevisionID)
        #expect(original.deletedAt == discardedAt.addingTimeInterval(-1))
        #expect(originalSuggestion.deletedAt == discardedAt)
        #expect(rebuiltSuggestion.deletedAt == discardedAt)

        let deletedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        try handler.softDelete(rebuilt, context: context, now: deletedAt, deviceID: "local")
        let visible = InboxSuggestionIdentityService().visibleLogicalItems(
            from: try context.fetch(FetchDescriptor<InboxItem>())
        )
        #expect(visible.isEmpty)
    }

    @Test @MainActor
    func titleEditRotatesRevisionAndReenablesSuggestions() throws {
        let context = try makeTestContext()
        let item = InboxItem(title: "Plan review", deviceID: "test")
        let dismissedRevisionID = item.effectiveSuggestionRevisionID
        item.dismissedSuggestionRevisionID = dismissedRevisionID
        item.suggestionGeneratedAt = Date(timeIntervalSinceReferenceDate: 100)
        context.insert(item)
        try context.save()

        try InboxCommandHandler().updateTitle(
            item,
            title: "Plan physics review",
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 200),
            deviceID: "local"
        )

        #expect(item.effectiveSuggestionRevisionID != dismissedRevisionID)
        #expect(item.dismissedSuggestionRevisionID == nil)
        #expect(item.suggestionGeneratedAt == nil)
        #expect(
            InboxSuggestionStateService().state(
                for: item,
                suggestion: nil,
                isInFlight: false
            ) == .eligible
        )
    }

    @Test @MainActor
    func staleRowToggleMutatesCurrentLogicalWinnerWithoutRestoringOldTitle() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let contextID = UUID()
        let stale = InboxItem(title: "Old title", deviceID: "old-device")
        stale.suggestionContextID = contextID
        stale.suggestionRevisionID = UUID()
        stale.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let current = InboxItem(title: "Current title", deviceID: "new-device")
        current.suggestionContextID = contextID
        current.suggestionRevisionID = UUID()
        current.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        context.insert(stale)
        context.insert(current)
        try context.save()

        let toggledAt = Date(timeIntervalSinceReferenceDate: 300)
        try handler.toggle(stale, context: context, now: toggledAt, deviceID: "local")

        let winner = try #require(
            InboxSuggestionIdentityService().visibleLogicalItems(
                from: try context.fetch(FetchDescriptor<InboxItem>())
            ).first
        )
        #expect(winner === current)
        #expect(winner.title == "Current title")
        #expect(winner.isCompleted)
        #expect(stale.deletedAt == toggledAt.addingTimeInterval(-1))
    }

    @Test @MainActor
    func staleRevisionDiscardDoesNotDismissOrReplaceCurrentRevision() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let contextID = UUID()
        let stale = InboxItem(title: "Old title", deviceID: "old-device")
        stale.suggestionContextID = contextID
        stale.suggestionRevisionID = UUID()
        stale.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let current = InboxItem(title: "Current title", deviceID: "new-device")
        current.suggestionContextID = contextID
        current.suggestionRevisionID = UUID()
        current.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        context.insert(stale)
        context.insert(current)
        try context.save()

        try handler.discardSuggestion(
            stale,
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 300),
            deviceID: "local"
        )

        let winner = try #require(
            InboxSuggestionIdentityService().visibleLogicalItems(
                from: try context.fetch(FetchDescriptor<InboxItem>())
            ).first
        )
        #expect(winner === current)
        #expect(winner.dismissedSuggestionRevisionID == nil)
        #expect(stale.dismissedSuggestionRevisionID == nil)
    }

    @Test @MainActor
    func newerLogicalTombstoneSuppressesOlderActivePhysicalSibling() {
        let contextID = UUID()
        let revisionID = UUID()
        let active = InboxItem(title: "Delete me", deviceID: "old")
        active.suggestionContextID = contextID
        active.suggestionRevisionID = revisionID
        active.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let tombstone = InboxItem(title: active.title, deviceID: "new")
        tombstone.suggestionContextID = contextID
        tombstone.suggestionRevisionID = revisionID
        tombstone.deletedAt = Date(timeIntervalSinceReferenceDate: 200)
        tombstone.updatedAt = tombstone.deletedAt ?? tombstone.updatedAt

        #expect(
            InboxSuggestionIdentityService().visibleLogicalItems(from: [active, tombstone]).isEmpty
        )
    }

    @Test @MainActor
    func upsertAndApplyCollapseLogicalSiblingsAndSuggestions() throws {
        let context = try makeTestContext()
        let handler = InboxCommandHandler()
        let task = TaskNode(title: "Destination", parentID: nil, deviceID: "test")
        let original = InboxItem(title: "Route once", deviceID: "first")
        let rebuilt = InboxItem(title: original.title, deviceID: "second")
        rebuilt.suggestionContextID = original.effectiveSuggestionContextID
        rebuilt.suggestionRevisionID = original.effectiveSuggestionRevisionID
        context.insert(task)
        context.insert(original)
        context.insert(rebuilt)
        try context.save()

        let generatedAt = Date(timeIntervalSinceReferenceDate: 100)
        try handler.upsertSuggestion(
            item: rebuilt,
            result: LLMInboxSuggestionResult(
                taskID: task.id,
                reason: "Same project",
                iconName: "checkmark.circle",
                colorHex: "1677FF",
                modelID: "test"
            ),
            context: context,
            now: generatedAt,
            deviceID: "local"
        )
        #expect(original.deletedAt == generatedAt.addingTimeInterval(-1))
        #expect(
            InboxSuggestionIdentityService().visibleLogicalItems(
                from: try context.fetch(FetchDescriptor<InboxItem>())
            ).first?.id == rebuilt.id
        )

        let generatedSuggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())
            .filter { $0.deletedAt == nil }
        let generated = try #require(generatedSuggestions.first)
        let duplicate = makeSuggestion(item: original, taskID: task.id)
        duplicate.updatedAt = Date(timeIntervalSinceReferenceDate: 50)
        context.insert(duplicate)
        try context.save()

        let appliedAt = Date(timeIntervalSinceReferenceDate: 200)
        _ = try handler.applySuggestion(
            item: rebuilt,
            suggestion: generated,
            existingChecklistItems: [],
            context: context,
            now: appliedAt,
            deviceID: "local"
        )

        let allItems = try context.fetch(FetchDescriptor<InboxItem>())
        let allSuggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())
        #expect(allItems.allSatisfy { $0.deletedAt != nil })
        #expect(allSuggestions.allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).count == 1)
    }

    @MainActor
    private func makeSuggestion(item: InboxItem, taskID: UUID) -> InboxSuggestion {
        InboxSuggestion(
            inboxItemID: item.id,
            inboxItemContextID: item.effectiveSuggestionContextID,
            inboxItemRevisionID: item.effectiveSuggestionRevisionID,
            taskID: taskID,
            titleSnapshot: item.title,
            deviceID: item.deviceID
        )
    }
}
