import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct InboxSuggestionSyncIdentityTests {
    @Test @MainActor
    func legacySnapshotRestoresDismissalAndExportsOpaqueIdentity() throws {
        let sourceContext = try makeTestContext()
        let legacyItem = InboxItem(title: "Private title must not become identity", deviceID: "legacy")
        legacyItem.suggestionContextID = nil
        legacyItem.suggestionRevisionID = nil
        legacyItem.dismissedSuggestionRevisionID = nil
        legacyItem.suggestionGeneratedAt = Date(timeIntervalSinceReferenceDate: 100)
        sourceContext.insert(legacyItem)
        try sourceContext.save()

        let captured = try SyncDataSnapshot.capture(context: sourceContext)
        let encoder = JSONEncoder()
        let capturedData = try encoder.encode(captured)
        var legacyJSON = try #require(
            JSONSerialization.jsonObject(with: capturedData) as? [String: Any]
        )
        var legacyItems = try #require(legacyJSON["inboxItems"] as? [[String: Any]])
        for index in legacyItems.indices {
            legacyItems[index].removeValue(forKey: "suggestionContextID")
            legacyItems[index].removeValue(forKey: "suggestionRevisionID")
            legacyItems[index].removeValue(forKey: "dismissedSuggestionRevisionID")
        }
        legacyJSON["inboxItems"] = legacyItems
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        let decoded = try JSONDecoder().decode(SyncDataSnapshot.self, from: legacyData)

        let restoredContext = try makeTestContext()
        try decoded.restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 200)
        )
        let restored = try #require(
            try restoredContext.fetch(FetchDescriptor<InboxItem>()).first
        )
        #expect(restored.suggestionContextID == legacyItem.id)
        #expect(restored.suggestionRevisionID == legacyItem.id)
        #expect(restored.dismissedSuggestionRevisionID == legacyItem.id)
        #expect(
            InboxSuggestionStateService().state(
                for: restored,
                suggestion: nil,
                isInFlight: false
            ) == .dismissed
        )

        let exportedData = try encoder.encode(
            SyncDataSnapshot.capture(context: restoredContext)
        )
        let exportedJSON = try #require(String(data: exportedData, encoding: .utf8))
        #expect(exportedJSON.contains("suggestionContextID"))
        #expect(exportedJSON.contains("suggestionRevisionID"))
        #expect(exportedJSON.contains("dismissedSuggestionRevisionID"))
        #expect(exportedJSON.contains("titleHash") == false)
        #expect(exportedJSON.contains("normalizedTitle") == false)
    }

    @Test @MainActor
    func snapshotRestoreSupersedesTombstonedPhysicalSibling() throws {
        let contextID = UUID()
        let revisionID = UUID()
        let sourceContext = try makeTestContext()
        let restoredItem = InboxItem(title: "Restore me", deviceID: "snapshot")
        restoredItem.suggestionContextID = contextID
        restoredItem.suggestionRevisionID = revisionID
        restoredItem.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        sourceContext.insert(restoredItem)
        try sourceContext.save()
        let snapshot = try SyncDataSnapshot.capture(context: sourceContext)

        let targetContext = try makeTestContext()
        let tombstone = InboxItem(title: restoredItem.title, deviceID: "local")
        tombstone.suggestionContextID = contextID
        tombstone.suggestionRevisionID = revisionID
        tombstone.deletedAt = Date(timeIntervalSinceReferenceDate: 150)
        tombstone.updatedAt = tombstone.deletedAt ?? tombstone.updatedAt
        targetContext.insert(tombstone)
        try targetContext.save()

        let restoreDate = Date(timeIntervalSinceReferenceDate: 200)
        try snapshot.restoreAsLocalWinner(context: targetContext, now: restoreDate)
        let allItems = try targetContext.fetch(FetchDescriptor<InboxItem>())
        let winner = try #require(
            InboxSuggestionIdentityService().visibleLogicalItems(from: allItems).first
        )

        #expect(winner.id == restoredItem.id)
        #expect(winner.deletedAt == nil)
        #expect(tombstone.deletedAt == restoreDate.addingTimeInterval(-1))
    }

    @Test @MainActor
    func restoreDoesNotInferDismissalWhenLogicalSiblingOwnsActiveSuggestion() throws {
        let sourceContext = try makeTestContext()
        let contextID = UUID()
        let revisionID = UUID()
        let task = TaskNode(title: "Target", parentID: nil, deviceID: "test")
        let original = InboxItem(title: "Shared suggestion", deviceID: "first")
        original.suggestionContextID = contextID
        original.suggestionRevisionID = revisionID
        original.createdAt = Date(timeIntervalSinceReferenceDate: 100)
        original.updatedAt = original.createdAt
        original.suggestionGeneratedAt = original.createdAt
        let rebuilt = InboxItem(title: original.title, deviceID: "second")
        rebuilt.suggestionContextID = contextID
        rebuilt.suggestionRevisionID = revisionID
        rebuilt.createdAt = Date(timeIntervalSinceReferenceDate: 200)
        rebuilt.updatedAt = rebuilt.createdAt
        rebuilt.suggestionGeneratedAt = rebuilt.createdAt
        let suggestion = makeSuggestion(item: original, taskID: task.id)
        sourceContext.insert(task)
        sourceContext.insert(original)
        sourceContext.insert(rebuilt)
        sourceContext.insert(suggestion)
        try sourceContext.save()

        let snapshot = try SyncDataSnapshot.capture(context: sourceContext)
        let targetContext = try makeTestContext()
        try snapshot.restoreAsLocalWinner(
            context: targetContext,
            now: Date(timeIntervalSinceReferenceDate: 300)
        )
        let items = try targetContext.fetch(FetchDescriptor<InboxItem>())
        let suggestions = try targetContext.fetch(FetchDescriptor<InboxSuggestion>())
        let restoredRebuilt = try #require(items.first { $0.id == rebuilt.id })
        let winner = try #require(
            InboxSuggestionIdentityService().visibleLogicalItems(from: items).first
        )
        let indexed = InboxSuggestionIdentityService().index(
            items: [winner],
            suggestions: suggestions
        )[winner.id]

        #expect(restoredRebuilt.dismissedSuggestionRevisionID == nil)
        #expect(indexed?.id == suggestion.id)
        #expect(
            InboxSuggestionStateService().state(
                for: winner,
                suggestion: indexed,
                isInFlight: false
            ) == .ready
        )
    }

    @Test @MainActor
    func restorePreflightRejectsProvablyMismatchedSuggestionIdentity() {
        let item = InboxItem(title: "Expected item", deviceID: "test")
        let suggestion = InboxSuggestion(
            inboxItemID: item.id,
            inboxItemContextID: UUID(),
            inboxItemRevisionID: item.effectiveSuggestionRevisionID,
            taskID: UUID(),
            titleSnapshot: item.title,
            deviceID: "test"
        )
        let snapshot = SyncDataSnapshot(
            inboxItems: [InboxItemRecord(item)],
            inboxSuggestions: [InboxSuggestionRecord(suggestion)]
        )

        #expect(throws: SyncDataSnapshotPreflightError.inconsistentInboxSuggestionIdentity(
            id: suggestion.id,
            inboxItemID: item.id
        )) {
            try snapshot.validateForRestore()
        }
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
