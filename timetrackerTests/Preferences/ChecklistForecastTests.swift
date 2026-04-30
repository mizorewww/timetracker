import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct ChecklistForecastTests {
    @Test @MainActor
    func checklistChangesImmediatelyRecalculateForecastEstimates() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Forecast Task", parentID: nil, colorHex: nil, iconName: nil)
        let end = Date().addingTimeInterval(-60)

        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: end.addingTimeInterval(-3_600),
            endedAt: end,
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        var firstDraft = TaskEditorDraft(task: task, checklistItems: [])
        firstDraft.checklistItems = [
            ChecklistEditorDraft(title: "Done", isCompleted: true),
            ChecklistEditorDraft(title: "Todo", isCompleted: false)
        ]
        store.saveTaskDraft(firstDraft)

        let firstRollup = try #require(store.rollup(for: task.id))
        #expect(firstRollup.checklistProgress.label == "1/2")
        #expect(firstRollup.estimatedTotalSeconds == 7_200)
        #expect(firstRollup.remainingSeconds == 3_600)
        #expect(firstRollup.historicalDailyAverageSeconds == 3_600)
        #expect(firstRollup.historicalActiveDayCount == 1)
        #expect(abs((firstRollup.projectedDays ?? 0) - 1.0) < 0.05)

        var secondDraft = TaskEditorDraft(task: task, checklistItems: store.checklistItems(for: task.id))
        secondDraft.checklistItems.append(ChecklistEditorDraft(title: "Also done", isCompleted: true))
        store.saveTaskDraft(secondDraft)

        let secondRollup = try #require(store.rollup(for: task.id))
        #expect(secondRollup.checklistProgress.label == "2/3")
        #expect(secondRollup.estimatedTotalSeconds == 5_400)
        #expect(secondRollup.remainingSeconds == 1_800)
        #expect(secondRollup.historicalDailyAverageSeconds == 3_600)
        #expect(secondRollup.historicalActiveDayCount == 1)
        #expect(abs((secondRollup.projectedDays ?? 0) - 0.5) < 0.05)
    }

    @Test @MainActor
    func checklistToggleImmediatelyRecalculatesForecastEstimates() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Toggle Forecast Task", parentID: nil, colorHex: nil, iconName: nil)
        let end = Date().addingTimeInterval(-60)

        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: end.addingTimeInterval(-3_600),
            endedAt: end,
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        var draft = TaskEditorDraft(task: task, checklistItems: [])
        draft.checklistItems = [
            ChecklistEditorDraft(title: "Already done", isCompleted: true),
            ChecklistEditorDraft(title: "Tap me", isCompleted: false)
        ]
        store.saveTaskDraft(draft)

        let firstRollup = try #require(store.rollup(for: task.id))
        #expect(firstRollup.checklistProgress.label == "1/2")
        #expect(firstRollup.estimatedTotalSeconds == 7_200)
        #expect(firstRollup.remainingSeconds == 3_600)

        let itemToToggle = try #require(store.checklistItems(for: task.id).first { $0.title == "Tap me" })
        store.toggleChecklistItem(itemToToggle)

        let secondRollup = try #require(store.rollup(for: task.id))
        #expect(secondRollup.checklistProgress.label == "2/2")
        #expect(secondRollup.estimatedTotalSeconds == 3_600)
        #expect(secondRollup.remainingSeconds == 0)
        #expect(secondRollup.projectedDays == 0)
        #expect(secondRollup.forecastState == .completed)
    }

    @Test @MainActor
    func checklistForecastRequiresCompletedItemAndTrackedTime() throws {
        let taskWithNoCompletedItem = TaskNode(title: "No completed item", parentID: nil, deviceID: "test")
        let taskWithNoTime = TaskNode(title: "No tracked time", parentID: nil, deviceID: "test")
        let start = Date(timeIntervalSince1970: 10_000)
        let segments = [
            TimeSegment(sessionID: UUID(), taskID: taskWithNoCompletedItem.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(1_800))
        ]
        let checklist = [
            ChecklistItem(taskID: taskWithNoCompletedItem.id, title: "First", isCompleted: false, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: taskWithNoCompletedItem.id, title: "Second", isCompleted: false, sortOrder: 20, deviceID: "test"),
            ChecklistItem(taskID: taskWithNoTime.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: taskWithNoTime.id, title: "Todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]

        let rollups = TaskRollupService().rollups(
            tasks: [taskWithNoCompletedItem, taskWithNoTime],
            segments: segments,
            checklistItems: checklist,
            now: start.addingTimeInterval(2_000)
        )

        #expect(rollups[taskWithNoCompletedItem.id]?.estimatedTotalSeconds == nil)
        #expect(rollups[taskWithNoCompletedItem.id]?.remainingSeconds == nil)
        #expect(rollups[taskWithNoCompletedItem.id]?.forecastState == .needsCompletedItem)
        #expect(rollups[taskWithNoCompletedItem.id]?.isDisplayableForecast == false)
        #expect(rollups[taskWithNoTime.id]?.estimatedTotalSeconds == nil)
        #expect(rollups[taskWithNoTime.id]?.remainingSeconds == nil)
        #expect(rollups[taskWithNoTime.id]?.forecastState == .needsTrackedTime)
        #expect(rollups[taskWithNoTime.id]?.isDisplayableForecast == false)
    }

    @Test @MainActor
    func forecastDaysUseOnlyThisTasksHistoricalTrackedDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOne = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 9)))
        let dayTwo = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 22, hour: 9)))
        let task = TaskNode(title: "Forecast Task", parentID: nil, deviceID: "test")
        let unrelated = TaskNode(title: "Unrelated", parentID: nil, deviceID: "test")
        let segments = [
            TimeSegment(sessionID: UUID(), taskID: task.id, source: .timer, deviceID: "test", startedAt: dayOne, endedAt: dayOne.addingTimeInterval(3_600)),
            TimeSegment(sessionID: UUID(), taskID: task.id, source: .timer, deviceID: "test", startedAt: dayTwo, endedAt: dayTwo.addingTimeInterval(7_200)),
            TimeSegment(sessionID: UUID(), taskID: unrelated.id, source: .timer, deviceID: "test", startedAt: dayOne, endedAt: dayOne.addingTimeInterval(36_000))
        ]
        let checklist = [
            ChecklistItem(taskID: task.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Todo 1", isCompleted: false, sortOrder: 20, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Todo 2", isCompleted: false, sortOrder: 30, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Todo 3", isCompleted: false, sortOrder: 40, deviceID: "test")
        ]

        let rollups = TaskRollupService().rollups(
            tasks: [task, unrelated],
            segments: segments,
            checklistItems: checklist,
            now: dayTwo.addingTimeInterval(10_000)
        )
        let rollup = try #require(rollups[task.id])

        #expect(rollup.workedSeconds == 10_800)
        #expect(rollup.estimatedTotalSeconds == 43_200)
        #expect(rollup.remainingSeconds == 32_400)
        #expect(rollup.historicalDailyAverageSeconds == 5_400)
        #expect(rollup.historicalActiveDayCount == 2)
        #expect(abs((rollup.projectedDays ?? 0) - 6.0) < 0.05)
    }

    @Test @MainActor
    func taskRollupRecursivelyCombinesChecklistAndChildEstimates() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        let grandchild = TaskNode(title: "Grandchild", parentID: child.id, deviceID: "test")
        grandchild.estimatedSeconds = 1_200
        let start = Date(timeIntervalSince1970: 10_000)
        let segments = [
            TimeSegment(sessionID: UUID(), taskID: parent.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(1_000)),
            TimeSegment(sessionID: UUID(), taskID: child.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(600)),
            TimeSegment(sessionID: UUID(), taskID: grandchild.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(300))
        ]
        let checklist = [
            ChecklistItem(taskID: parent.id, title: "One", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: parent.id, title: "Two", isCompleted: false, sortOrder: 20, deviceID: "test"),
            ChecklistItem(taskID: child.id, title: "A", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: child.id, title: "B", isCompleted: true, sortOrder: 20, deviceID: "test")
        ]

        let rollups = TaskRollupService().rollups(tasks: [parent, child, grandchild], segments: segments, checklistItems: checklist, now: start.addingTimeInterval(2_000))
        let parentRollup = try #require(rollups[parent.id])

        #expect(parentRollup.workedSeconds == 1_900)
        #expect(parentRollup.estimatedTotalSeconds == 2_900)
        #expect(parentRollup.remainingSeconds == 1_000)
        #expect(parentRollup.historicalDailyAverageSeconds == 1_900)
        #expect(parentRollup.historicalActiveDayCount == 1)
        #expect(abs((parentRollup.projectedDays ?? 0) - 0.53) < 0.05)
        #expect(parentRollup.checklistProgress.label == "1/2")
        #expect(parentRollup.confidence == .medium)
        #expect(parentRollup.forecastState == .ready)
    }

    @Test @MainActor
    func taskRollupHandlesMissingDataDeletedChecklistAndCompletedTasks() throws {
        let empty = TaskNode(title: "Empty", parentID: nil, deviceID: "test")
        let planned = TaskNode(title: "Planned", parentID: nil, deviceID: "test")
        planned.estimatedSeconds = 900
        let completed = TaskNode(title: "Done", parentID: nil, deviceID: "test")
        completed.status = .completed
        completed.estimatedSeconds = 3_600
        let deletedChecklist = ChecklistItem(taskID: planned.id, title: "Removed", isCompleted: true, sortOrder: 10, deviceID: "test")
        deletedChecklist.deletedAt = Date()

        let rollups = TaskRollupService().rollups(tasks: [empty, planned, completed], segments: [], checklistItems: [deletedChecklist])

        #expect(rollups[empty.id]?.estimatedTotalSeconds == nil)
        #expect(rollups[empty.id]?.confidence == ForecastConfidence.none)
        #expect(rollups[empty.id]?.forecastState == .needsChecklist)
        #expect(rollups[planned.id]?.checklistProgress.totalCount == 0)
        #expect(rollups[planned.id]?.estimatedTotalSeconds == nil)
        #expect(rollups[planned.id]?.forecastState == .needsChecklist)
        #expect(rollups[completed.id]?.remainingSeconds == 0)
        #expect(rollups[completed.id]?.forecastState == .completed)
    }

    @Test @MainActor
    func onlyChecklistBackedForecastsAreDisplayable() throws {
        let historyOnly = TaskNode(title: "History Only", parentID: nil, deviceID: "test")
        let manual = TaskNode(title: "Manual", parentID: nil, deviceID: "test")
        manual.estimatedSeconds = 1_800
        let checklistTask = TaskNode(title: "Checklist", parentID: nil, deviceID: "test")
        let start = Date(timeIntervalSince1970: 10_000)
        let segments = [
            TimeSegment(sessionID: UUID(), taskID: historyOnly.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(600)),
            TimeSegment(sessionID: UUID(), taskID: checklistTask.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(900))
        ]
        let checklist = [
            ChecklistItem(taskID: checklistTask.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: checklistTask.id, title: "Todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]

        let rollups = TaskRollupService().rollups(
            tasks: [historyOnly, manual, checklistTask],
            segments: segments,
            checklistItems: checklist,
            now: start.addingTimeInterval(2_000)
        )

        #expect(rollups[historyOnly.id]?.forecastState == .needsChecklist)
        #expect(rollups[historyOnly.id]?.isDisplayableForecast == false)
        #expect(rollups[manual.id]?.forecastState == .needsChecklist)
        #expect(rollups[manual.id]?.isDisplayableForecast == false)
        #expect(rollups[checklistTask.id]?.isDisplayableForecast == true)
    }

    @Test @MainActor
    func forecastDisplayServiceDrillsIntoSingleChildButAggregatesMultipleChildren() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let firstChild = TaskNode(title: "First", parentID: parent.id, deviceID: "test")
        let secondChild = TaskNode(title: "Second", parentID: parent.id, deviceID: "test")
        let start = Date(timeIntervalSince1970: 20_000)
        let firstSegment = TimeSegment(sessionID: UUID(), taskID: firstChild.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(1_200))
        let secondSegment = TimeSegment(sessionID: UUID(), taskID: secondChild.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(600))
        let firstChecklist = [
            ChecklistItem(taskID: firstChild.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: firstChild.id, title: "Todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]
        let firstOnlyRollups = TaskRollupService().rollups(
            tasks: [parent, firstChild, secondChild],
            segments: [firstSegment],
            checklistItems: firstChecklist,
            now: start.addingTimeInterval(2_000)
        )

        let firstOnlyDisplay = ForecastDisplayService().displayItems(
            tasks: [parent, firstChild, secondChild],
            rollups: firstOnlyRollups
        )
        #expect(firstOnlyDisplay.map(\.taskID) == [firstChild.id])

        let secondChecklist = [
            ChecklistItem(taskID: secondChild.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: secondChild.id, title: "Todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]
        let multiRollups = TaskRollupService().rollups(
            tasks: [parent, firstChild, secondChild],
            segments: [firstSegment, secondSegment],
            checklistItems: firstChecklist + secondChecklist,
            now: start.addingTimeInterval(2_000)
        )

        let multiDisplay = ForecastDisplayService().displayItems(
            tasks: [parent, firstChild, secondChild],
            rollups: multiRollups
        )
        #expect(multiDisplay.map(\.taskID) == [parent.id])
        #expect(multiRollups[parent.id]?.forecastState == .aggregate)
        #expect(multiRollups[parent.id]?.forecastSourceTaskIDs.count == 2)
    }

    @Test @MainActor
    func parentForecastIncludesChildForecastsWhenOwnChecklistIsIncomplete() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        let start = Date(timeIntervalSince1970: 30_000)
        let childSegment = TimeSegment(sessionID: UUID(), taskID: child.id, source: .timer, deviceID: "test", startedAt: start, endedAt: start.addingTimeInterval(1_200))
        let checklist = [
            ChecklistItem(taskID: parent.id, title: "Parent todo", isCompleted: false, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: child.id, title: "Child done", isCompleted: true, sortOrder: 10, deviceID: "test"),
            ChecklistItem(taskID: child.id, title: "Child todo", isCompleted: false, sortOrder: 20, deviceID: "test")
        ]
        let rollups = TaskRollupService().rollups(
            tasks: [parent, child],
            segments: [childSegment],
            checklistItems: checklist,
            now: start.addingTimeInterval(2_000)
        )
        let parentRollup = try #require(rollups[parent.id])

        #expect(parentRollup.forecastState == .aggregate)
        #expect(parentRollup.remainingSeconds == 1_200)
        #expect(parentRollup.estimatedTotalSeconds == 2_400)
        #expect(parentRollup.forecastSourceTaskIDs == [child.id])
        #expect(parentRollup.forecastSourceLabel == String(format: AppStrings.localized("forecast.source.aggregate"), 1))
        #expect(ForecastDisplayService().displayItem(for: parent.id, tasks: [parent, child], rollups: rollups)?.taskID == parent.id)
        #expect(ForecastDisplayService().displayItems(tasks: [parent, child], rollups: rollups).map(\.taskID) == [parent.id])
    }
}
