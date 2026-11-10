import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct LegacySchemaMigrationTests {
    @Test @MainActor
    func versionEightStoreMigratesToCurrentSchemaWithoutTheLegacyDailySummaryCache() throws {
        let fixture = try LegacyStoreFixture.create(
            name: "LegacyV8",
            schema: TimeTrackerSchemaV8.self
        ) { context in
            let task = TaskNode(title: "V8 task", parentID: nil, deviceID: "legacy")
            let summary = DailySummary(
                date: Date(timeIntervalSinceReferenceDate: 100_000),
                taskID: task.id,
                grossSeconds: 900,
                wallClockSeconds: 900,
                pomodoroCount: 1,
                interruptionCount: 0
            )
            context.insert(task)
            context.insert(summary)
            return task.id
        }

        try fixture.withCurrentContext { context in
            let taskIDs = try context.fetch(FetchDescriptor<TaskNode>()).map(\.id)
            #expect(taskIDs == [fixture.seed])
            #expect(TimeTrackerModelRegistry.currentSchema.entity(for: DailySummary.self) == nil)
        }
    }

    @Test @MainActor
    func versionNineStoreMigratesInboxSuggestionIdentityAndDismissalState() throws {
        let fixture = try LegacyStoreFixture.create(
            name: "LegacyV9",
            schema: TimeTrackerSchemaV9.self
        ) { context in
            let task = TaskNode(title: "Migration target", parentID: nil, deviceID: "legacy")
            let dismissedItem = TimeTrackerSchemaV9.InboxItem(
                title: "Dismissed before migration",
                deviceID: "legacy"
            )
            dismissedItem.suggestionGeneratedAt = Date(timeIntervalSinceReferenceDate: 100)
            let readyItem = TimeTrackerSchemaV9.InboxItem(
                title: "Suggestion survives migration",
                deviceID: "legacy"
            )
            readyItem.suggestedTaskID = task.id
            readyItem.suggestionGeneratedAt = Date(timeIntervalSinceReferenceDate: 200)
            let suggestion = TimeTrackerSchemaV9.InboxSuggestion(
                inboxItemID: readyItem.id,
                taskID: task.id,
                titleSnapshot: readyItem.title,
                deviceID: "legacy"
            )

            context.insert(task)
            context.insert(dismissedItem)
            context.insert(readyItem)
            context.insert(suggestion)
            return (
                dismissedItemID: dismissedItem.id,
                readyItemID: readyItem.id,
                suggestionID: suggestion.id
            )
        }

        try fixture.withCurrentContext { context in
            let items = try context.fetch(FetchDescriptor<InboxItem>())
            let suggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())
            let dismissedItem = try #require(items.first { $0.id == fixture.seed.dismissedItemID })
            let readyItem = try #require(items.first { $0.id == fixture.seed.readyItemID })
            let suggestion = try #require(suggestions.first { $0.id == fixture.seed.suggestionID })

            #expect(dismissedItem.suggestionContextID == fixture.seed.dismissedItemID)
            #expect(dismissedItem.suggestionRevisionID == fixture.seed.dismissedItemID)
            #expect(dismissedItem.dismissedSuggestionRevisionID == fixture.seed.dismissedItemID)
            #expect(
                InboxSuggestionStateService.state(
                    for: dismissedItem,
                    suggestion: nil,
                    isInFlight: false
                ) == .dismissed
            )
            #expect(readyItem.suggestionContextID == fixture.seed.readyItemID)
            #expect(readyItem.suggestionRevisionID == fixture.seed.readyItemID)
            #expect(readyItem.dismissedSuggestionRevisionID == nil)
            #expect(suggestion.inboxItemContextID == fixture.seed.readyItemID)
            #expect(suggestion.inboxItemRevisionID == fixture.seed.readyItemID)
            #expect(suggestion.belongs(to: readyItem))
        }
    }

    @Test @MainActor
    func versionElevenSuggestionMigratesToChecklistDestination() throws {
        let fixture = try LegacyStoreFixture.create(
            name: "LegacyV11",
            schema: TimeTrackerSchemaV11.self
        ) { context in
            let task = TaskNode(title: "Legacy destination", parentID: nil, deviceID: "legacy")
            let item = InboxItem(title: "Legacy suggestion", deviceID: "legacy")
            let suggestion = TimeTrackerSchemaV11.InboxSuggestion(
                inboxItemID: item.id,
                inboxItemContextID: item.effectiveSuggestionContextID,
                inboxItemRevisionID: item.effectiveSuggestionRevisionID,
                taskID: task.id,
                reason: "V11 reason",
                iconName: "archivebox",
                colorHex: "FF9500",
                modelID: "legacy-model",
                titleSnapshot: item.title,
                generatedAt: Date(timeIntervalSinceReferenceDate: 120_000),
                deviceID: "legacy"
            )
            context.insert(task)
            context.insert(item)
            context.insert(suggestion)
            return (inboxItemID: item.id, suggestionID: suggestion.id, taskID: task.id)
        }

        try fixture.withCurrentContext { context in
            let suggestion = try #require(
                try context.fetch(FetchDescriptor<InboxSuggestion>())
                    .first { $0.id == fixture.seed.suggestionID }
            )

            #expect(suggestion.inboxItemID == fixture.seed.inboxItemID)
            #expect(suggestion.taskID == fixture.seed.taskID)
            #expect(suggestion.reason == "V11 reason")
            #expect(suggestion.iconName == "archivebox")
            #expect(suggestion.colorHex == "FF9500")
            #expect(suggestion.modelID == "legacy-model")
            #expect(suggestion.destinationKindRaw == InboxSuggestionDestinationKind.checklist.rawValue)
            #expect(suggestion.destinationKind == .checklist)
        }
    }

    @Test @MainActor
    func versionTwelveStoreMigratesToTaskProgressSchema() throws {
        let fixture = try LegacyStoreFixture.create(
            name: "LegacyV12TaskPlanning",
            schema: TimeTrackerSchemaV12.self,
            directoryPrefix: "LegacyV12"
        ) { context in
            let task = TaskNode(
                title: "V12 preserved task",
                parentID: nil,
                deviceID: "legacy"
            )
            context.insert(task)
            return task.id
        }

        try fixture.withCurrentContext { context in
            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            let task = try #require(tasks.first { $0.id == fixture.seed })

            #expect(task.title == "V12 preserved task")
            let rule = TaskRecurrenceRule(
                templateTaskID: task.id,
                startDayKey: "2026-07-20",
                timeZoneIdentifier: "Asia/Singapore",
                deviceID: "test"
            )
            let occurrence = TaskRecurrenceOccurrence(
                ruleID: rule.id,
                templateTaskID: task.id,
                occurrenceDayKey: "2026-07-20",
                timeZoneIdentifier: rule.timeZoneIdentifier,
                deviceID: "test"
            )
            let goal = TaskQuantityGoal(
                taskID: task.id,
                targetAmount: 50,
                unitLabel: "push-ups",
                deviceID: "test"
            )
            let entry = TaskQuantityEntry(
                id: UUID(),
                taskID: task.id,
                amount: 20,
                deviceID: "test"
            )
            context.insert(rule)
            context.insert(occurrence)
            context.insert(goal)
            context.insert(entry)
            try context.save()

            #expect(try context.fetch(FetchDescriptor<TaskRecurrenceRule>()).map(\.id) == [rule.id])
            #expect(
                try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                    .map(\.generatedTaskID) == [occurrence.generatedTaskID]
            )
            #expect(try context.fetch(FetchDescriptor<TaskQuantityGoal>()).map(\.id) == [goal.id])
            #expect(
                try context.fetch(FetchDescriptor<TaskQuantityEntry>())
                    .map(\.quantityGoalID) == [goal.id]
            )
        }
    }
}
