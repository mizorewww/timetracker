import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct InboxSuggestionApplyBoundaryTests {
    @Test @MainActor
    func tombstonedSuggestionCannotBeApplied() throws {
        let context = try makeTestContext()
        let item = InboxItem(title: "Keep this capture", deviceID: "test")
        let suggestion = makeSuggestion(for: item)
        suggestion.deletedAt = Date(timeIntervalSinceReferenceDate: 200)
        suggestion.updatedAt = suggestion.deletedAt ?? suggestion.updatedAt
        context.insert(item)
        context.insert(suggestion)
        try context.save()

        try expectStaleApply(item: item, suggestion: suggestion, context: context)

        #expect(suggestion.deletedAt == Date(timeIntervalSinceReferenceDate: 200))
    }

    @Test @MainActor
    func nonCanonicalActiveSiblingCannotBeApplied() throws {
        let context = try makeTestContext()
        let item = InboxItem(title: "Keep the latest route", deviceID: "test")
        let stale = makeSuggestion(for: item)
        stale.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let canonical = makeSuggestion(for: item)
        canonical.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        context.insert(item)
        context.insert(stale)
        context.insert(canonical)
        try context.save()

        try expectStaleApply(item: item, suggestion: stale, context: context)

        #expect(stale.deletedAt == nil)
        #expect(canonical.deletedAt == nil)
    }

    @Test @MainActor
    func detachedSuggestionFromAnOldRefreshCannotBeApplied() throws {
        let context = try makeTestContext()
        let item = InboxItem(title: "Use the stored route", deviceID: "test")
        let canonical = makeSuggestion(for: item)
        canonical.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        context.insert(item)
        context.insert(canonical)
        try context.save()

        let detachedStale = makeSuggestion(for: item)
        detachedStale.updatedAt = Date(timeIntervalSinceReferenceDate: 100)

        try expectStaleApply(item: item, suggestion: detachedStale, context: context)

        #expect(canonical.deletedAt == nil)
    }

    @Test @MainActor
    func suggestionForAnOlderTitleCannotBeApplied() throws {
        let context = try makeTestContext()
        let item = InboxItem(title: "Current title", deviceID: "test")
        let suggestion = makeSuggestion(for: item, titleSnapshot: "Previous title")
        context.insert(item)
        context.insert(suggestion)
        try context.save()

        try expectStaleApply(item: item, suggestion: suggestion, context: context)

        #expect(suggestion.deletedAt == nil)
    }

    @Test @MainActor
    func dismissalOnAnOlderLogicalSiblingPreventsApply() throws {
        let context = try makeTestContext()
        let contextID = UUID()
        let revisionID = UUID()
        let dismissedSibling = InboxItem(title: "Keep this capture", deviceID: "old")
        dismissedSibling.suggestionContextID = contextID
        dismissedSibling.suggestionRevisionID = revisionID
        dismissedSibling.dismissedSuggestionRevisionID = revisionID
        dismissedSibling.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let item = InboxItem(title: dismissedSibling.title, deviceID: "new")
        item.suggestionContextID = contextID
        item.suggestionRevisionID = revisionID
        item.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        let suggestion = makeSuggestion(for: item)
        context.insert(dismissedSibling)
        context.insert(item)
        context.insert(suggestion)
        try context.save()

        try expectStaleApply(item: item, suggestion: suggestion, context: context)

        #expect(item.dismissedSuggestionRevisionID == nil)
        #expect(dismissedSibling.deletedAt == nil)
        #expect(suggestion.deletedAt == nil)
    }

    @MainActor
    private func expectStaleApply(
        item: InboxItem,
        suggestion: InboxSuggestion,
        context: ModelContext
    ) throws {
        let originalItemUpdatedAt = item.updatedAt
        let originalItemMutationID = item.clientMutationID
        #expect(throws: InboxCommandIdentityError.self) {
            _ = try InboxCommandHandler().applySuggestion(
                item: item,
                suggestion: suggestion,
                existingChecklistItems: [],
                context: context,
                now: Date(timeIntervalSinceReferenceDate: 1000),
                deviceID: "local"
            )
        }

        #expect(item.deletedAt == nil)
        #expect(item.updatedAt == originalItemUpdatedAt)
        #expect(item.clientMutationID == originalItemMutationID)
        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
    }

    @MainActor
    private func makeSuggestion(
        for item: InboxItem,
        titleSnapshot: String? = nil
    ) -> InboxSuggestion {
        InboxSuggestion(
            inboxItemID: item.id,
            inboxItemContextID: item.effectiveSuggestionContextID,
            inboxItemRevisionID: item.effectiveSuggestionRevisionID,
            taskID: UUID(),
            reason: "Matched",
            iconName: "checkmark.circle",
            colorHex: "1677FF",
            modelID: "test",
            titleSnapshot: titleSnapshot ?? item.title,
            deviceID: "test"
        )
    }
}
