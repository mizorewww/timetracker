import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct InboxSuggestionSyncIdentityTests {
    @Test @MainActor
    func snapshotRoundTripPreservesDismissalAcrossSameIdentifierDuplicates() throws {
        let sourceContext = try makeTestContext()
        let sharedID = UUID()
        let contextID = UUID()
        let revisionID = UUID()
        let dismissed = InboxItem(title: "Dismiss once", deviceID: "older-device")
        dismissed.id = sharedID
        dismissed.suggestionContextID = contextID
        dismissed.suggestionRevisionID = revisionID
        dismissed.dismissedSuggestionRevisionID = revisionID
        dismissed.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let newerActive = InboxItem(title: dismissed.title, deviceID: "newer-device")
        newerActive.id = sharedID
        newerActive.suggestionContextID = contextID
        newerActive.suggestionRevisionID = revisionID
        newerActive.notes = "New notes"
        newerActive.isCompleted = true
        newerActive.completedAt = Date(timeIntervalSinceReferenceDate: 190)
        newerActive.sortOrder = 40
        newerActive.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        sourceContext.insert(dismissed)
        sourceContext.insert(newerActive)
        try sourceContext.save()

        let fullSnapshot = try SyncDataSnapshot.capture(context: sourceContext)
        let partialSnapshot = try SyncDataSnapshot.capture(
            context: sourceContext,
            updating: SyncDataSnapshot(),
            domains: [.inbox]
        )
        for snapshot in [fullSnapshot, partialSnapshot] {
            let captured = try #require(snapshot.inboxItems.first)
            #expect(snapshot.inboxItems.count == 1)
            #expect(captured.id == sharedID)
            #expect(captured.dismissedSuggestionRevisionID == revisionID)
            #expect(captured.notes == "New notes")
            #expect(captured.isCompleted)
            #expect(captured.completedAt == Date(timeIntervalSinceReferenceDate: 190))
            #expect(captured.sortOrder == 40)
        }

        let exported = try JSONEncoder().encode(fullSnapshot)
        let imported = try JSONDecoder().decode(SyncDataSnapshot.self, from: exported)
        let captured = try #require(imported.inboxItems.first)
        #expect(imported.inboxItems.count == 1)
        #expect(captured.id == sharedID)
        #expect(captured.dismissedSuggestionRevisionID == revisionID)
        #expect(captured.notes == "New notes")
        #expect(captured.isCompleted)
        #expect(captured.completedAt == Date(timeIntervalSinceReferenceDate: 190))
        #expect(captured.sortOrder == 40)

        let restoredContext = try makeTestContext()
        try imported.restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 300)
        )
        let restored = try #require(
            try restoredContext.fetch(FetchDescriptor<InboxItem>()).first
        )
        #expect(restored.id == sharedID)
        #expect(restored.dismissedSuggestionRevisionID == revisionID)
        #expect(restored.notes == "New notes")
        #expect(restored.isCompleted)
        #expect(restored.completedAt == Date(timeIntervalSinceReferenceDate: 190))
        #expect(restored.sortOrder == 40)
        #expect(
            InboxSuggestionStateService().state(
                for: restored,
                suggestion: nil,
                isInFlight: false
            ) == .unavailable
        )
    }

    @Test @MainActor
    func snapshotRoundTripMergesDismissalIntoNewerLogicalSiblingFields() throws {
        let sourceContext = try makeTestContext()
        let contextID = UUID()
        let revisionID = UUID()
        let dismissed = InboxItem(title: "Shared capture", deviceID: "old")
        dismissed.suggestionContextID = contextID
        dismissed.suggestionRevisionID = revisionID
        dismissed.dismissedSuggestionRevisionID = revisionID
        dismissed.notes = "Old notes"
        dismissed.sortOrder = 10
        dismissed.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let newer = InboxItem(title: dismissed.title, deviceID: "new")
        newer.suggestionContextID = contextID
        newer.suggestionRevisionID = revisionID
        newer.notes = "New notes"
        newer.sortOrder = 40
        newer.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        sourceContext.insert(dismissed)
        sourceContext.insert(newer)
        try sourceContext.save()

        let encoded = try JSONEncoder().encode(
            SyncDataSnapshot.capture(context: sourceContext)
        )
        let snapshot = try JSONDecoder().decode(SyncDataSnapshot.self, from: encoded)
        #expect(snapshot.inboxItems.count == 2)
        let restoredContext = try makeTestContext()
        try snapshot.restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 300)
        )

        var store = InboxStore()
        store.refresh(
            items: try restoredContext.fetch(FetchDescriptor<InboxItem>()),
            suggestions: []
        )
        let winner = try #require(store.items.first)
        #expect(winner.id == newer.id)
        #expect(winner.notes == "New notes")
        #expect(winner.sortOrder == 40)
        #expect(winner.dismissedSuggestionRevisionID == revisionID)
        #expect(winner.isCurrentSuggestionRevisionDismissed)
    }

    @Test @MainActor
    func snapshotRestorePreservesCanonicalSuggestionOrdering() throws {
        let sourceContext = try makeTestContext()
        let task = TaskNode(title: "Target", parentID: nil, deviceID: "test")
        let item = InboxItem(title: "Choose the latest", deviceID: "test")
        item.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let canonical = makeSuggestion(item: item, taskID: task.id)
        canonical.id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        canonical.updatedAt = Date(timeIntervalSinceReferenceDate: 300)
        let stale = makeSuggestion(item: item, taskID: task.id)
        stale.id = try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        stale.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        sourceContext.insert(task)
        sourceContext.insert(item)
        sourceContext.insert(canonical)
        sourceContext.insert(stale)
        try sourceContext.save()

        let sourceWinner = InboxSuggestionIdentityService().index(
            items: [item],
            suggestions: [stale, canonical]
        )[item.id]
        #expect(sourceWinner?.id == canonical.id)

        let encoded = try JSONEncoder().encode(
            SyncDataSnapshot.capture(context: sourceContext)
        )
        let snapshot = try JSONDecoder().decode(SyncDataSnapshot.self, from: encoded)
        let restoredContext = try makeTestContext()
        try snapshot.restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 1_000)
        )

        let restoredItems = try restoredContext.fetch(FetchDescriptor<InboxItem>())
        let restoredItem = try #require(restoredItems.first { $0.id == item.id })
        let restoredSuggestions = try restoredContext.fetch(FetchDescriptor<InboxSuggestion>())
        let restoredCanonical = try #require(
            restoredSuggestions.first { $0.id == canonical.id }
        )
        let restoredStale = try #require(
            restoredSuggestions.first { $0.id == stale.id }
        )
        let restoredWinner = InboxSuggestionIdentityService().index(
            items: [restoredItem],
            suggestions: restoredSuggestions
        )[restoredItem.id]

        #expect(restoredCanonical.updatedAt == Date(timeIntervalSinceReferenceDate: 1_000))
        #expect(restoredStale.updatedAt == Date(timeIntervalSinceReferenceDate: 200))
        #expect(restoredWinner?.id == canonical.id)
    }

    @Test @MainActor
    func snapshotRoundTripPreservesSuggestionDestinationKind() throws {
        let sourceContext = try makeTestContext()
        let item = InboxItem(title: "Route to a category", deviceID: "source")
        let suggestion = makeSuggestion(item: item, taskID: UUID())
        suggestion.destinationKindRaw = InboxSuggestionDestinationKind.category.rawValue
        sourceContext.insert(item)
        sourceContext.insert(suggestion)
        try sourceContext.save()

        let captured = try SyncDataSnapshot.capture(context: sourceContext)
        let capturedRecord = try #require(captured.inboxSuggestions.first)
        #expect(
            capturedRecord.destinationKindRaw ==
                InboxSuggestionDestinationKind.category.rawValue
        )

        let encoded = try JSONEncoder().encode(captured)
        let encodedJSON = try #require(String(data: encoded, encoding: .utf8))
        #expect(encodedJSON.contains("\"destinationKindRaw\":\"category\""))
        let decoded = try JSONDecoder().decode(SyncDataSnapshot.self, from: encoded)
        try decoded.validateForRestore()
        #expect(
            decoded.inboxSuggestions.first?.destinationKindRaw ==
                InboxSuggestionDestinationKind.category.rawValue
        )

        let restoredContext = try makeTestContext()
        try decoded.restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 300)
        )
        let restored = try #require(
            try restoredContext.fetch(FetchDescriptor<InboxSuggestion>()).first
        )
        #expect(restored.destinationKind == .category)
        #expect(
            try SyncDataSnapshot.capture(context: restoredContext)
                .inboxSuggestions.first?.destinationKindRaw ==
                InboxSuggestionDestinationKind.category.rawValue
        )
    }

    @Test @MainActor
    func titleEditSnapshotAcceptsHistoricalSuggestionTombstone() throws {
        let sourceContext = try makeTestContext()
        let task = TaskNode(title: "Target", parentID: nil, deviceID: "test")
        let item = InboxItem(title: "Original title", deviceID: "test")
        let originalRevisionID = item.effectiveSuggestionRevisionID
        let suggestion = makeSuggestion(item: item, taskID: task.id)
        sourceContext.insert(task)
        sourceContext.insert(item)
        sourceContext.insert(suggestion)
        try sourceContext.save()

        let editDate = Date(timeIntervalSinceReferenceDate: 200)
        try InboxCommandHandler().updateTitle(
            item,
            title: "Edited title",
            context: sourceContext,
            now: editDate,
            deviceID: "test"
        )

        let snapshot = try SyncDataSnapshot.capture(context: sourceContext)
        let historicalSuggestion = try #require(
            snapshot.inboxSuggestions.first { $0.id == suggestion.id }
        )
        #expect(historicalSuggestion.inboxItemRevisionID == originalRevisionID)
        #expect(historicalSuggestion.deletedAt == editDate)
        try snapshot.validateForRestore()

        let restoredContext = try makeTestContext()
        try snapshot.restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 300)
        )
        let restoredItem = try #require(
            try restoredContext.fetch(FetchDescriptor<InboxItem>()).first { $0.id == item.id }
        )
        let restoredSuggestion = try #require(
            try restoredContext.fetch(FetchDescriptor<InboxSuggestion>()).first { $0.id == suggestion.id }
        )
        #expect(restoredItem.title == "Edited title")
        #expect(restoredItem.effectiveSuggestionRevisionID != originalRevisionID)
        #expect(restoredSuggestion.inboxItemRevisionID == originalRevisionID)
        #expect(restoredSuggestion.deletedAt != nil)
    }

    @Test @MainActor
    func snapshotRestorePreservesNewerLogicalRevisionWinner() throws {
        let sourceContext = try makeTestContext()
        let contextID = UUID()
        let current = makeLogicalItem(
            title: "Current revision",
            contextID: contextID,
            revisionID: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let stale = makeLogicalItem(
            title: "Stale revision",
            contextID: contextID,
            revisionID: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        sourceContext.insert(current)
        sourceContext.insert(stale)
        try sourceContext.save()

        let sourceWinner = try #require(
            InboxSuggestionIdentityService().visibleLogicalItems(from: [stale, current]).first
        )
        #expect(sourceWinner.id == current.id)

        let restoredContext = try makeTestContext()
        try SyncDataSnapshot.capture(context: sourceContext).restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        let restoredItems = try restoredContext.fetch(FetchDescriptor<InboxItem>())
        let restoredWinner = try #require(
            InboxSuggestionIdentityService().visibleLogicalItems(from: restoredItems).first
        )

        #expect(restoredWinner.id == current.id)
        #expect(restoredWinner.title == "Current revision")
    }

    @Test @MainActor
    func snapshotRestorePreservesNewerActiveRestoreOverOlderTombstone() throws {
        let sourceContext = try makeTestContext()
        let contextID = UUID()
        let restored = makeLogicalItem(
            title: "Restored",
            contextID: contextID,
            revisionID: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            updatedAt: Date(timeIntervalSinceReferenceDate: 300)
        )
        let tombstone = makeLogicalItem(
            title: "Deleted before restore",
            contextID: contextID,
            revisionID: UUID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 200),
            updatedAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        tombstone.deletedAt = tombstone.updatedAt
        sourceContext.insert(restored)
        sourceContext.insert(tombstone)
        try sourceContext.save()

        let sourceWinner = try #require(
            InboxSuggestionIdentityService().logicalWinners(from: [tombstone, restored]).first
        )
        #expect(sourceWinner.id == restored.id)
        #expect(sourceWinner.deletedAt == nil)

        let restoredContext = try makeTestContext()
        try SyncDataSnapshot.capture(context: sourceContext).restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 1_000)
        )
        let restoredItems = try restoredContext.fetch(FetchDescriptor<InboxItem>())
        let restoredWinner = try #require(
            InboxSuggestionIdentityService().logicalWinners(from: restoredItems).first
        )

        #expect(restoredWinner.id == restored.id)
        #expect(restoredWinner.deletedAt == nil)
    }

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
        legacyJSON.removeValue(forKey: "inboxCaptureReceipts")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        let decoded = try JSONDecoder().decode(SyncDataSnapshot.self, from: legacyData)

        #expect(decoded.inboxCaptureReceipts == nil)

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
    func legacySnapshotWithoutSuggestionDestinationKindRestoresAsChecklist() throws {
        let sourceContext = try makeTestContext()
        let item = InboxItem(title: "Legacy suggestion", deviceID: "legacy")
        let suggestion = makeSuggestion(item: item, taskID: UUID())
        suggestion.destinationKindRaw = InboxSuggestionDestinationKind.childTask.rawValue
        sourceContext.insert(item)
        sourceContext.insert(suggestion)
        try sourceContext.save()

        let encoder = JSONEncoder()
        let capturedData = try encoder.encode(
            SyncDataSnapshot.capture(context: sourceContext)
        )
        var legacyJSON = try #require(
            JSONSerialization.jsonObject(with: capturedData) as? [String: Any]
        )
        var legacySuggestions = try #require(
            legacyJSON["inboxSuggestions"] as? [[String: Any]]
        )
        #expect(legacySuggestions.first?["destinationKindRaw"] as? String == "childTask")
        for index in legacySuggestions.indices {
            legacySuggestions[index].removeValue(forKey: "destinationKindRaw")
        }
        legacyJSON["inboxSuggestions"] = legacySuggestions
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)

        let decoded = try JSONDecoder().decode(SyncDataSnapshot.self, from: legacyData)
        let decodedSuggestion = try #require(decoded.inboxSuggestions.first)
        #expect(decodedSuggestion.destinationKindRaw == "checklist")
        try decoded.validateForRestore()

        let restoredContext = try makeTestContext()
        try decoded.restoreAsLocalWinner(
            context: restoredContext,
            now: Date(timeIntervalSinceReferenceDate: 300)
        )
        let restored = try #require(
            try restoredContext.fetch(FetchDescriptor<InboxSuggestion>()).first
        )
        #expect(restored.destinationKind == .checklist)

        let exportedData = try encoder.encode(
            SyncDataSnapshot.capture(context: restoredContext)
        )
        var exportedJSON = try #require(
            JSONSerialization.jsonObject(with: exportedData) as? [String: Any]
        )
        let exportedSuggestions = try #require(
            exportedJSON.removeValue(forKey: "inboxSuggestions") as? [[String: Any]]
        )
        #expect(exportedSuggestions.first?["destinationKindRaw"] as? String == "checklist")
    }

    @Test @MainActor
    func explicitNullSuggestionDestinationKindIsNotTreatedAsLegacyData() throws {
        let context = try makeTestContext()
        let item = InboxItem(title: "Malformed suggestion", deviceID: "source")
        let suggestion = makeSuggestion(item: item, taskID: UUID())
        context.insert(item)
        context.insert(suggestion)
        try context.save()

        let capturedData = try JSONEncoder().encode(
            SyncDataSnapshot.capture(context: context)
        )
        var malformedJSON = try #require(
            JSONSerialization.jsonObject(with: capturedData) as? [String: Any]
        )
        var suggestions = try #require(
            malformedJSON["inboxSuggestions"] as? [[String: Any]]
        )
        suggestions[0]["destinationKindRaw"] = NSNull()
        malformedJSON["inboxSuggestions"] = suggestions
        let malformedData = try JSONSerialization.data(
            withJSONObject: malformedJSON
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                SyncDataSnapshot.self,
                from: malformedData
            )
        }
    }

    @Test
    func legacySnapshotMergeDoesNotTreatMissingReceiptTableAsAnEmptyTable() throws {
        let item = InboxItem(title: "Existing receipt item", deviceID: "test")
        let receipt = InboxCaptureReceipt(
            commandKey: "test.integration\u{1F}\(UUID().uuidString.lowercased())",
            payloadFingerprint: String(repeating: "a", count: 64),
            inboxItemID: item.id,
            deviceID: "test"
        )
        var local = SyncDataSnapshot(
            inboxItems: [InboxItemRecord(item)],
            inboxCaptureReceipts: [InboxCaptureReceiptRecord(receipt)]
        )
        let legacyBaseline = SyncDataSnapshot()
        let legacyUpdated = SyncDataSnapshot()

        local.applyChanges(from: legacyBaseline, to: legacyUpdated)

        #expect(local.inboxCaptureReceipts == [InboxCaptureReceiptRecord(receipt)])
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

    @MainActor
    private func makeLogicalItem(
        title: String,
        contextID: UUID,
        revisionID: UUID,
        createdAt: Date,
        updatedAt: Date
    ) -> InboxItem {
        let item = InboxItem(title: title, deviceID: "test")
        item.suggestionContextID = contextID
        item.suggestionRevisionID = revisionID
        item.createdAt = createdAt
        item.updatedAt = updatedAt
        return item
    }
}
