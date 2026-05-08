import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct DataModelContractTests {
    @Test @MainActor
    func modelDefaultsSupportCloudKitCompatibleConstruction() throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Defaults", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test")
        let segment = TimeSegment(sessionID: session.id, taskID: task.id, source: .timer, deviceID: "test")
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        let summary = DailySummary(date: Date(), taskID: task.id, grossSeconds: 0, wallClockSeconds: 0, pomodoroCount: 0, interruptionCount: 0)
        let countdown = CountdownEvent(title: "Launch", date: Date(), deviceID: "test")
        let preference = SyncedPreference(key: AppPreferenceKey.defaultFocusMinutes.rawValue, valueJSON: "25", deviceID: "test")
        let checklistItem = ChecklistItem(taskID: task.id, title: "Checklist", deviceID: "test")
        let checklistVisual = ChecklistItemVisual(checklistItemID: checklistItem.id, iconName: "book", colorHex: "16A34A", deviceID: "test")
        let inboxItem = InboxItem(title: "Inbox", deviceID: "test")
        let inboxSuggestion = InboxSuggestion(
            inboxItemID: inboxItem.id,
            taskID: task.id,
            reason: "Related",
            iconName: "book",
            colorHex: "16A34A",
            modelID: "test",
            titleSnapshot: inboxItem.title,
            deviceID: "test"
        )
        let category = TaskCategory(title: "Work", deviceID: "test")
        let categoryAssignment = TaskCategoryAssignment(taskID: task.id, categoryID: category.id, deviceID: "test")

        context.insert(task)
        context.insert(category)
        context.insert(categoryAssignment)
        context.insert(session)
        context.insert(segment)
        context.insert(run)
        context.insert(summary)
        context.insert(countdown)
        context.insert(preference)
        context.insert(checklistItem)
        context.insert(checklistVisual)
        context.insert(inboxItem)
        context.insert(inboxSuggestion)
        try context.save()

        #expect(task.id.uuidString.isEmpty == false)
        #expect(task.status == .active)
        #expect(segment.source == .timer)
        #expect(run.state == .planned)
        #expect(summary.version == 1)
        #expect(countdown.deletedAt == nil)
        #expect(preference.deletedAt == nil)
        #expect(checklistItem.deletedAt == nil)
        #expect(checklistVisual.deletedAt == nil)
        #expect(checklistVisual.suggestionTitleSnapshot == nil)
        #expect(checklistVisual.userEditedAt == nil)
        #expect(inboxSuggestion.deletedAt == nil)
        #expect(category.includesInForecast)
        #expect(categoryAssignment.deletedAt == nil)
    }

    @Test @MainActor
    func cloudSyncedSchemaIncludesChecklistAndAllUserDataModels() throws {
        let requiredModelNames: Set<String> = [
            "TaskNode",
            "TaskCategory",
            "TaskCategoryAssignment",
            "TimeSession",
            "TimeSegment",
            "PomodoroRun",
            "CountdownEvent",
            "SyncedPreference",
            "ChecklistItem",
            "ChecklistItemVisual",
            "InboxItem",
            "InboxSuggestion"
        ]

        #expect(requiredModelNames.isSubset(of: TimeTrackerModelRegistry.cloudSyncedUserModelNames))

        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "TimeTrackerCloudSyncContract",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let task = TaskNode(title: "Cloud task", parentID: nil, deviceID: "test")
        let category = TaskCategory(title: "Cloud category", deviceID: "test")
        let assignment = TaskCategoryAssignment(taskID: task.id, categoryID: category.id, deviceID: "test")
        let checklist = ChecklistItem(taskID: task.id, title: "Cloud checklist", deviceID: "test")
        let checklistVisual = ChecklistItemVisual(checklistItemID: checklist.id, iconName: "book", colorHex: "16A34A", deviceID: "test")
        let inboxItem = InboxItem(title: "Cloud inbox", deviceID: "test")
        let inboxSuggestion = InboxSuggestion(
            inboxItemID: inboxItem.id,
            taskID: task.id,
            reason: "Cloud reason",
            iconName: "book",
            colorHex: "16A34A",
            modelID: "test",
            titleSnapshot: inboxItem.title,
            deviceID: "test"
        )
        let preference = SyncedPreference(key: AppPreferenceKey.showGrossAndWallTogether.rawValue, valueJSON: "true", deviceID: "test")

        context.insert(task)
        context.insert(category)
        context.insert(assignment)
        context.insert(checklist)
        context.insert(checklistVisual)
        context.insert(inboxItem)
        context.insert(inboxSuggestion)
        context.insert(preference)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).map(\.title) == ["Cloud checklist"])
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).map(\.iconName) == ["book"])
        #expect(try context.fetch(FetchDescriptor<InboxItem>()).map(\.title) == ["Cloud inbox"])
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).map(\.taskID) == [task.id])
        #expect(try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).map(\.categoryID) == [category.id])
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).map(\.key) == [AppPreferenceKey.showGrossAndWallTogether.rawValue])
    }

    @Test @MainActor
    func applyingInboxSuggestionCreatesChecklistWithVisualAndRemovesInboxItem() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: "1677FF", iconName: "paintbrush")
        let inboxItem = InboxItem(title: "Polish empty state", deviceID: "test")
        let suggestion = InboxSuggestion(
            inboxItemID: inboxItem.id,
            taskID: task.id,
            reason: "Same design project",
            iconName: "paintbrush",
            colorHex: "1677FF",
            modelID: "gpt-test",
            titleSnapshot: inboxItem.title,
            deviceID: "test"
        )
        context.insert(inboxItem)
        context.insert(suggestion)
        try context.save()

        _ = try InboxCommandHandler().applySuggestion(
            item: inboxItem,
            suggestion: suggestion,
            existingChecklistItems: [],
            context: context,
            deviceID: "test"
        )

        let checklistItems = try context.fetch(FetchDescriptor<ChecklistItem>())
        let visuals = try context.fetch(FetchDescriptor<ChecklistItemVisual>())
        #expect(checklistItems.map(\.title) == ["Polish empty state"])
        #expect(checklistItems.first?.taskID == task.id)
        #expect(visuals.map(\.iconName) == ["paintbrush"])
        #expect(visuals.map(\.colorHex) == ["1677FF"])
        #expect(visuals.map(\.suggestionTitleSnapshot) == ["Polish empty state"])
        #expect(visuals.map(\.suggestionModelID) == ["gpt-test"])
        #expect(inboxItem.deletedAt != nil)
        #expect(suggestion.deletedAt != nil)
    }

    @Test @MainActor
    func taskStatusCanBePlannedAndCompleted() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(title: "Plan draft", parentID: nil, colorHex: nil, iconName: nil)

        try repository.setTaskStatus(taskID: task.id, status: .planned)
        #expect(try repository.task(id: task.id)?.status == .planned)

        try repository.setTaskStatus(taskID: task.id, status: .completed)
        #expect(try repository.task(id: task.id)?.status == .completed)
        #expect(TaskStatus.completed.displayName == AppStrings.localized("status.completed"))
    }

    @Test @MainActor
    func csvExportIncludesLedgerRows() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "CSV Task", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 2_000)
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            note: "Export note"
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let csv = store.csvExport()

        #expect(csv.contains("Task,Path,Start,End,Duration Seconds,Source,Note"))
        #expect(csv.contains("CSV Task"))
        #expect(csv.contains("900"))
        #expect(csv.contains("Export note"))
    }
}
