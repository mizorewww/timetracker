import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLogicalWinnerRestoreTests {
    @Test @MainActor
    func preferenceRestorePreservesSourceWinnerAndSupersedesTargetSibling() throws {
        let source = try makeTestContext()
        let key = AppPreferenceKey.defaultFocusMinutes.rawValue
        let base = Date(timeIntervalSinceReferenceDate: 100_000)
        let winnerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let staleID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

        let winner = SyncedPreference(
            key: key,
            valueJSON: PreferenceJSON.encode(50),
            deviceID: "source-a"
        )
        winner.id = winnerID
        winner.createdAt = base
        winner.updatedAt = base.addingTimeInterval(20)
        let stale = SyncedPreference(
            key: key,
            valueJSON: PreferenceJSON.encode(10),
            deviceID: "source-b"
        )
        stale.id = staleID
        stale.createdAt = base.addingTimeInterval(10)
        stale.updatedAt = base.addingTimeInterval(5)
        source.insert(winner)
        source.insert(stale)
        try source.save()
        let snapshot = try SyncDataSnapshot.capture(context: source)

        let target = try makeTestContext()
        let targetSibling = SyncedPreference(
            key: key,
            valueJSON: PreferenceJSON.encode(99),
            deviceID: "target"
        )
        targetSibling.createdAt = base.addingTimeInterval(15)
        targetSibling.updatedAt = base.addingTimeInterval(15)
        target.insert(targetSibling)
        try target.save()

        let restoreDate = base.addingTimeInterval(100)
        try snapshot.restoreAsLocalWinner(context: target, now: restoreDate)
        let restored = try target.fetch(FetchDescriptor<SyncedPreference>())
        let logicalWinner = try #require(SyncedPreferenceService.latestByKey(restored)[key])

        #expect(logicalWinner.id == winnerID)
        #expect(logicalWinner.valueJSON == PreferenceJSON.encode(50))
        #expect(logicalWinner.updatedAt == restoreDate)
        #expect(logicalWinner.deletedAt == nil)
        #expect(restored.first(where: { $0.id == staleID })?.updatedAt == base.addingTimeInterval(5))
        #expect(restored.first(where: { $0.id == targetSibling.id })?.updatedAt == restoreDate.addingTimeInterval(-1))
    }

    @Test @MainActor
    func categoryAssignmentRestorePreservesSourceWinnerAndSupersedesTargetSibling() throws {
        let source = try makeTestContext()
        let base = Date(timeIntervalSinceReferenceDate: 200_000)
        let taskID = UUID()
        let winnerCategoryID = UUID()
        let staleCategoryID = UUID()
        let winnerID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let staleID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000002"))

        let winner = TaskCategoryAssignment(
            taskID: taskID,
            categoryID: winnerCategoryID,
            deviceID: "source-a"
        )
        winner.id = winnerID
        winner.createdAt = base
        winner.updatedAt = base.addingTimeInterval(20)
        let stale = TaskCategoryAssignment(
            taskID: taskID,
            categoryID: staleCategoryID,
            deviceID: "source-b"
        )
        stale.id = staleID
        stale.createdAt = base.addingTimeInterval(10)
        stale.updatedAt = base.addingTimeInterval(5)
        source.insert(winner)
        source.insert(stale)
        try source.save()
        let snapshot = try SyncDataSnapshot.capture(context: source)

        let target = try makeTestContext()
        let targetSibling = TaskCategoryAssignment(
            taskID: taskID,
            categoryID: UUID(),
            deviceID: "target"
        )
        targetSibling.createdAt = base.addingTimeInterval(15)
        targetSibling.updatedAt = base.addingTimeInterval(15)
        target.insert(targetSibling)
        try target.save()

        let restoreDate = base.addingTimeInterval(100)
        try snapshot.restoreAsLocalWinner(context: target, now: restoreDate)
        let restored = try target.fetch(FetchDescriptor<TaskCategoryAssignment>())
        let logicalWinner = try #require(restored.logicalWinnersByTaskID()[taskID])

        #expect(logicalWinner.id == winnerID)
        #expect(logicalWinner.categoryID == winnerCategoryID)
        #expect(logicalWinner.updatedAt == restoreDate)
        #expect(logicalWinner.deletedAt == nil)
        #expect(restored.first(where: { $0.id == staleID })?.updatedAt == base.addingTimeInterval(5))
        #expect(restored.first(where: { $0.id == targetSibling.id })?.updatedAt == restoreDate.addingTimeInterval(-1))
    }
}
