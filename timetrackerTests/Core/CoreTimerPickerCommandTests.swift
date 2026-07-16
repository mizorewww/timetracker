import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreTimerPickerCommandTests {
    @Test
    func policyNamesStartParallelStartAndSwitchModesExplicitly() {
        let policy = TimerPickerCommandPolicy()

        #expect(policy.mode(hasActiveTimers: false, allowParallelTimers: false) == .start)
        #expect(policy.mode(hasActiveTimers: false, allowParallelTimers: true) == .start)
        #expect(policy.mode(hasActiveTimers: true, allowParallelTimers: true) == .startAnother)
        #expect(policy.mode(hasActiveTimers: true, allowParallelTimers: false) == .switchTimer)
        #expect(policy.selectionCommand(isTaskRunning: true, mode: .startAnother) == .alreadyRunning)
        #expect(policy.selectionCommand(isTaskRunning: false, mode: .startAnother) == .start)
        #expect(policy.selectionCommand(isTaskRunning: false, mode: .switchTimer) == .switchTimer)
    }

    @Test @MainActor
    func selectingARunningTaskIsANoOpUntilStopIsExplicit() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Already running",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)
        let store = makeTestStore()
        store.configureRepositoriesIfNeeded(context: context)
        store.tasks = [task]
        store.activeSegments = [segment]

        let outcome = store.performTimerPickerSelection(task)

        #expect(outcome == .alreadyRunning)
        #expect(try timeRepository.activeSegments().map(\.id) == [segment.id])
        #expect(segment.endedAt == nil)

        store.stop(segment: segment)

        #expect(try timeRepository.activeSegments().isEmpty)
        #expect(segment.endedAt != nil)
    }

    @Test @MainActor
    func exclusiveSelectionReportsSwitchAndReplacesTheOtherTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(
            title: "Current task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let nextTask = try taskRepository.createTask(
            title: "Next task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let firstSegment = try timeRepository.startTask(taskID: firstTask.id, source: .timer)
        let store = makeTestStore()
        store.configureRepositoriesIfNeeded(context: context)
        store.tasks = [firstTask, nextTask]
        store.activeSegments = [firstSegment]
        store.preferences.allowParallelTimers = false

        let outcome = store.performTimerPickerSelection(nextTask)
        let activeSegments = try timeRepository.activeSegments()

        #expect(outcome == .switched)
        #expect(firstSegment.endedAt != nil)
        #expect(activeSegments.count == 1)
        #expect(activeSegments.first?.taskID == nextTask.id)
    }

    @Test @MainActor
    func parallelSelectionReportsStartAndPreservesTheOtherTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(
            title: "First task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let nextTask = try taskRepository.createTask(
            title: "Parallel task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let firstSegment = try timeRepository.startTask(taskID: firstTask.id, source: .timer)
        let store = makeTestStore()
        store.configureRepositoriesIfNeeded(context: context)
        store.tasks = [firstTask, nextTask]
        store.activeSegments = [firstSegment]
        store.preferences.allowParallelTimers = true

        let outcome = store.performTimerPickerSelection(nextTask)
        let activeSegments = try timeRepository.activeSegments()

        #expect(outcome == .started)
        #expect(firstSegment.endedAt == nil)
        #expect(Set(activeSegments.map(\.taskID)) == [firstTask.id, nextTask.id])
    }
}
