import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TodayHeatmapRecurrenceStoreTests {
    @Test @MainActor
    func generatedPreferenceAndDetailCommandsUseTheTemplateHeatmap() async throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "heatmap-store-test"
        )
        let template = try repository.createTask(
            title: "Daily push-ups",
            parentID: nil,
            colorHex: "7C3AED",
            iconName: "figure.strengthtraining.traditional"
        )
        let rule = TaskRecurrenceRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-23",
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "heatmap-store-test"
        )
        context.insert(rule)
        let occurrence = TaskRecurrenceOccurrence(
            ruleID: rule.id,
            templateTaskID: template.id,
            occurrenceDayKey: "2026-07-23",
            timeZoneIdentifier: rule.timeZoneIdentifier,
            deviceID: "heatmap-store-test"
        )
        let generated = try repository.createGeneratedRecurrenceTask(
            id: occurrence.generatedTaskID,
            template: template,
            occurrenceDayKey: occurrence.occurrenceDayKey,
            now: Date(timeIntervalSinceReferenceDate: 806_068_800)
        )
        context.insert(occurrence)

        let templateGoal = TaskQuantityGoal(
            taskID: template.id,
            targetAmount: 50,
            unitLabel: "reps",
            deviceID: "heatmap-store-test"
        )
        let generatedGoal = TaskQuantityGoal(
            taskID: generated.id,
            targetAmount: 50,
            unitLabel: "reps",
            deviceID: "heatmap-store-test"
        )
        let entry = TaskQuantityEntry(
            id: UUID(),
            taskID: generated.id,
            amount: 25,
            recordedAt: Date(timeIntervalSinceReferenceDate: 806_068_800),
            createdAt: Date(timeIntervalSinceReferenceDate: 806_068_800),
            deviceID: "heatmap-store-test"
        )
        context.insert(templateGoal)
        context.insert(generatedGoal)
        context.insert(entry)
        context.insert(
            SyncedPreference(
                key: AppPreferenceKey.todayHeatmapTaskIDs.rawValue,
                valueJSON: PreferenceJSON.encode([generated.id.uuidString]),
                deviceID: "heatmap-store-test"
            )
        )
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(store.preferences.todayHeatmapTaskIDs == [generated.id])
        #expect(store.todayHeatmapSelectedTaskIDs == [template.id])
        #expect(store.todayHeatmapRenderableTaskIDs == [template.id])
        #expect(store.todayHeatmapOwnerTaskID(for: generated.id) == template.id)
        #expect(store.todayHeatmapSelectableTaskIDs.contains(template.id))
        #expect(store.todayHeatmapSelectableTaskIDs.contains(generated.id) == false)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let now = Date(timeIntervalSinceReferenceDate: 806_112_000)
        let request = HomeActivityHeatmapRefreshRequest(
            store: store,
            now: now,
            calendar: calendar,
            clockRevision: 0
        )
        #expect(request.selectedTaskIDs == [template.id])
        let snapshot = try #require(
            await store.todayTaskActivityHeatmapSnapshots(
                period: .oneMonth,
                now: now,
                calendar: calendar
            ).first
        )
        #expect(snapshot.taskID == template.id)
        #expect(snapshot.metric == .quantity(unitLabel: "reps"))
        #expect(snapshot.totalValue == 25)

        #expect(store.setTodayHeatmapTrackingEnabled(false, for: generated.id))
        #expect(store.preferences.todayHeatmapTaskIDs.isEmpty)
        #expect(store.setTodayHeatmapTrackingEnabled(true, for: generated.id))
        #expect(store.preferences.todayHeatmapTaskIDs == [template.id])
        #expect(
            store.setTodayHeatmapTaskIDs([
                generated.id,
                template.id,
                generated.id,
            ])
        )
        #expect(store.preferences.todayHeatmapTaskIDs == [template.id])
    }
}
