import Foundation
import Testing
@testable import timetracker

struct CoreSyncSnapshotMergeTests {
    private let baseDate = Date(timeIntervalSinceReferenceDate: 700_000)

    private func taskRecord(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date,
        createdAt: Date? = nil,
        deletedAt: Date? = nil
    ) -> TaskRecord {
        let task = TaskNode(title: title, parentID: nil, deviceID: "merge-test")
        task.id = id
        task.createdAt = createdAt ?? baseDate
        task.updatedAt = updatedAt
        task.deletedAt = deletedAt
        return TaskRecord(task)
    }

    @Test
    func unionKeepsRecordsUniqueToEitherSide() {
        let sharedID = UUID()
        let local = [
            taskRecord(id: sharedID, title: "shared", updatedAt: baseDate),
            taskRecord(title: "local only", updatedAt: baseDate),
        ]
        let cloud = [
            taskRecord(id: sharedID, title: "shared", updatedAt: baseDate),
            taskRecord(title: "cloud only", updatedAt: baseDate),
        ]

        let merged = local.mergedByIDLWW(with: cloud)

        #expect(merged.count == 3)
        #expect(merged.map(\.title).contains("local only"))
        #expect(merged.map(\.title).contains("cloud only"))
    }

    @Test
    func newerUpdatedAtWinsRegardlessOfArgumentOrder() {
        let id = UUID()
        let older = taskRecord(id: id, title: "older", updatedAt: baseDate)
        let newer = taskRecord(id: id, title: "newer", updatedAt: baseDate.addingTimeInterval(60))

        #expect([older].mergedByIDLWW(with: [newer]).first?.title == "newer")
        #expect([newer].mergedByIDLWW(with: [older]).first?.title == "newer")
    }

    @Test
    func tombstoneWinsAnEqualTimestamp() {
        let id = UUID()
        let visible = taskRecord(id: id, title: "visible", updatedAt: baseDate)
        let tombstone = taskRecord(id: id, title: "tombstone", updatedAt: baseDate, deletedAt: baseDate)

        let merged = [visible].mergedByIDLWW(with: [tombstone])

        #expect(merged.count == 1)
        #expect(merged.first?.deletedAt != nil)
    }

    @Test
    func equalTimestampsBreakTheTieDeterministicallyByContent() {
        let id = UUID()
        let first = taskRecord(id: id, title: "alpha", updatedAt: baseDate)
        let second = taskRecord(id: id, title: "omega", updatedAt: baseDate)

        let forward = [first].mergedByIDLWW(with: [second])
        let reversed = [second].mergedByIDLWW(with: [first])

        #expect(forward == reversed)
        #expect(forward.count == 1)
    }

    @Test
    func mergedResultIsSortedByIDSoFingerprintsAreStable() {
        let ids = (0 ..< 4).map { _ in UUID() }
        let local = ids.map { taskRecord(id: $0, title: "t", updatedAt: baseDate) }
        let merged = local.mergedByIDLWW(with: [])

        #expect(merged.map(\.id.uuidString) == ids.map(\.uuidString).sorted())
    }

    @Test
    func preferencesMergeByLogicalKeyNotPhysicalID() {
        func preference(
            id: UUID = UUID(),
            key: String,
            value: String,
            updatedAt: Date
        ) -> SyncedPreferenceRecord {
            let model = SyncedPreference(key: key, valueJSON: value, deviceID: "merge-test")
            model.id = id
            model.createdAt = baseDate
            model.updatedAt = updatedAt
            return SyncedPreferenceRecord(model)
        }

        var local = SyncDataSnapshot()
        local.syncedPreferences = [
            preference(key: "theme", value: "\"dark\"", updatedAt: baseDate),
        ]
        var cloud = SyncDataSnapshot()
        cloud.syncedPreferences = [
            preference(key: "theme", value: "\"light\"", updatedAt: baseDate.addingTimeInterval(30)),
            preference(key: "cloud-only", value: "1", updatedAt: baseDate),
        ]

        let merged = local.mergedForAutoResolution(with: cloud)

        let themes = merged.syncedPreferences.filter { $0.key == "theme" }
        #expect(themes.count == 1)
        #expect(themes.first?.valueJSON == "\"light\"")
        #expect(merged.syncedPreferences.contains { $0.key == "cloud-only" })
    }

    @Test
    func optionalTablesTreatNilAsUnknownAndKeepTheKnownSide() {
        func rule(updatedAt: Date) -> TaskRecurrenceRuleRecord {
            let model = TaskRecurrenceRule(
                templateTaskID: UUID(),
                startDayKey: "2026-07-25",
                timeZoneIdentifier: "Asia/Singapore",
                deviceID: "merge-test"
            )
            model.createdAt = baseDate
            model.updatedAt = updatedAt
            return TaskRecurrenceRuleRecord(model)
        }

        var legacyLocal = SyncDataSnapshot()
        legacyLocal.taskRecurrenceRules = nil
        var currentCloud = SyncDataSnapshot()
        currentCloud.taskRecurrenceRules = [rule(updatedAt: baseDate)]

        let merged = legacyLocal.mergedForAutoResolution(with: currentCloud)
        #expect(merged.taskRecurrenceRules?.count == 1)

        var emptyCloud = SyncDataSnapshot()
        emptyCloud.taskRecurrenceRules = []
        let authoritativeEmpty = legacyLocal.mergedForAutoResolution(with: emptyCloud)
        #expect(authoritativeEmpty.taskRecurrenceRules == [])

        var bothLegacy = SyncDataSnapshot()
        bothLegacy.taskRecurrenceRules = nil
        let unknown = legacyLocal.mergedForAutoResolution(with: bothLegacy)
        #expect(unknown.taskRecurrenceRules == nil)
    }

    @Test
    func snapshotMergeAcrossEveryTableMatchesCloudWhenCloudDominates() throws {
        let id = UUID()
        var local = SyncDataSnapshot()
        local.tasks = [taskRecord(id: id, title: "older", updatedAt: baseDate)]
        var cloud = SyncDataSnapshot()
        cloud.tasks = [taskRecord(id: id, title: "newer", updatedAt: baseDate.addingTimeInterval(60))]
        cloud.checklistItems = {
            let item = ChecklistItem(taskID: id, title: "remote checklist", deviceID: "merge-test")
            item.createdAt = baseDate
            item.updatedAt = baseDate
            return [ChecklistItemRecord(item)]
        }()

        let merged = local.mergedForAutoResolution(with: cloud)

        #expect(merged == cloud)
        #expect(try merged.fingerprint() == cloud.fingerprint())
    }
}
