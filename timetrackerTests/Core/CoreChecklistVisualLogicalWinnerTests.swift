import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreChecklistVisualLogicalWinnerTests {
    @Test @MainActor
    func readPathUsesStableLogicalTieBreakAndHonorsTombstoneWinner() throws {
        let context = try makeTestContext()
        let itemID = UUID()
        let timestamp = Date(timeIntervalSinceReferenceDate: 300_000)
        let lowerID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000001"))
        let higherID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let lower = makeVisual(
            id: lowerID,
            itemID: itemID,
            iconName: "circle",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let higher = makeVisual(
            id: higherID,
            itemID: itemID,
            iconName: "star",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        context.insert(higher)
        context.insert(lower)
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(try store.fetchChecklistItemVisuals().map(\.id) == [higherID])

        higher.deletedAt = timestamp
        try context.save()
        #expect(try store.fetchChecklistItemVisuals().isEmpty)
    }

    @Test @MainActor
    func restorePreservesSourceVisualWinnerAndSupersedesTargetSibling() throws {
        let source = try makeTestContext()
        let itemID = UUID()
        let base = Date(timeIntervalSinceReferenceDate: 400_000)
        let winnerID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000001"))
        let staleID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000002"))
        let winner = makeVisual(
            id: winnerID,
            itemID: itemID,
            iconName: "checkmark.seal",
            createdAt: base,
            updatedAt: base.addingTimeInterval(20)
        )
        let stale = makeVisual(
            id: staleID,
            itemID: itemID,
            iconName: "xmark.seal",
            createdAt: base.addingTimeInterval(10),
            updatedAt: base.addingTimeInterval(5)
        )
        source.insert(winner)
        source.insert(stale)
        try source.save()
        let snapshot = try SyncDataSnapshot.capture(context: source)

        let target = try makeTestContext()
        let targetSibling = makeVisual(
            id: UUID(),
            itemID: itemID,
            iconName: "questionmark",
            createdAt: base.addingTimeInterval(15),
            updatedAt: base.addingTimeInterval(15)
        )
        target.insert(targetSibling)
        try target.save()

        let restoreDate = base.addingTimeInterval(100)
        try snapshot.restoreAsLocalWinner(context: target, now: restoreDate)
        let restored = try target.fetch(FetchDescriptor<ChecklistItemVisual>())
        let logicalWinner = try #require(restored.logicalWinnersByChecklistItemID()[itemID])

        #expect(logicalWinner.id == winnerID)
        #expect(logicalWinner.iconName == "checkmark.seal")
        #expect(logicalWinner.updatedAt == restoreDate)
        #expect(restored.first(where: { $0.id == staleID })?.updatedAt == base.addingTimeInterval(5))
        #expect(restored.first(where: { $0.id == targetSibling.id })?.updatedAt == restoreDate.addingTimeInterval(-1))
    }

    @MainActor
    private func makeVisual(
        id: UUID,
        itemID: UUID,
        iconName: String,
        createdAt: Date,
        updatedAt: Date
    ) -> ChecklistItemVisual {
        let visual = ChecklistItemVisual(
            checklistItemID: itemID,
            iconName: iconName,
            colorHex: "1677FF",
            deviceID: "test"
        )
        visual.id = id
        visual.createdAt = createdAt
        visual.updatedAt = updatedAt
        visual.clientMutationID = id
        return visual
    }
}
