import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskLedgerTests {
    @Test @MainActor
    func taskMovePreventsCyclesAndUpdatesHierarchy() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")

        let root = try repository.createTask(title: "Root", parentID: nil, colorHex: nil, iconName: nil)
        let child = try repository.createTask(title: "Child", parentID: root.id, colorHex: nil, iconName: nil)

        do {
            try repository.moveTask(taskID: root.id, newParentID: child.id, sortOrder: 10)
            Issue.record("Expected invalid move to throw")
        } catch TaskRepositoryError.invalidMove {
        } catch {
            Issue.record("Unexpected move error: \(error)")
        }
        #expect((try repository.task(id: root.id))?.parentID == nil)

        try repository.moveTask(taskID: child.id, newParentID: nil, sortOrder: 20)
        let movedTask = try repository.task(id: child.id)
        let moved = try #require(movedTask)
        #expect(moved.parentID == nil)
        #expect(moved.depth == 0)
    }

    @Test @MainActor
    func softDeletingParentRecursivelySoftDeletesDescendantsButKeepsLedger() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")

        let parent = try taskRepository.createTask(title: "Parent", parentID: nil, colorHex: nil, iconName: nil)
        let child = try taskRepository.createTask(title: "Child", parentID: parent.id, colorHex: nil, iconName: nil)
        let grandchild = try taskRepository.createTask(title: "Grandchild", parentID: child.id, colorHex: nil, iconName: nil)
        let segment = try timeRepository.addManualSegment(
            taskID: grandchild.id,
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            note: nil
        )

        try taskRepository.softDeleteTask(taskID: parent.id)

        #expect(try taskRepository.allNodes().isEmpty)
        let rawNodes = try context.fetch(FetchDescriptor<TaskNode>())
        #expect(rawNodes.count == 3)
        #expect(rawNodes.allSatisfy { $0.deletedAt != nil })
        #expect(try timeRepository.allSegments().contains { $0.id == segment.id })
    }

    @Test @MainActor
    func taskTreeServiceFiltersInvalidParentsAndFlattensVisibleRows() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        let grandchild = TaskNode(title: "Grandchild", parentID: child.id, deviceID: "test")
        let sibling = TaskNode(title: "Sibling", parentID: nil, deviceID: "test")
        let service = TaskTreeService()
        let indexes = service.indexes(tasks: [parent, child, grandchild, sibling])

        let validParents = service.validParentTasks(for: parent.id, tasks: [parent, child, grandchild, sibling])
        #expect(validParents.map(\.id) == [sibling.id])

        let rows = TaskTreeFlattener.visibleRows(
            rootTasks: indexes.childrenByParentID[nil] ?? [],
            children: { indexes.childrenByParentID[$0.id] ?? [] },
            expandedTaskIDs: [parent.id]
        )

        #expect(rows.map(\.taskID) == [parent.id, child.id, sibling.id])
        #expect(rows.map(\.depth) == [0, 1, 0])
        #expect(rows.first?.hasChildren == true)
        #expect(rows.first?.isExpanded == true)
    }

    @Test @MainActor
    func timerPauseResumeStopUsesSegmentsAsLedger() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: nil, iconName: nil)

        let first = try timeRepository.startTask(taskID: task.id, source: .timer)
        #expect(try timeRepository.activeSegments().count == 1)

        try timeRepository.pauseSession(sessionID: first.sessionID)
        #expect(try timeRepository.activeSegments().isEmpty)

        let resumedSegment = try timeRepository.resumeSession(sessionID: first.sessionID)
        let second = try #require(resumedSegment)
        #expect(second.sessionID == first.sessionID)
        #expect(try timeRepository.activeSegments().count == 1)

        try timeRepository.stopSession(sessionID: first.sessionID)
        #expect(try timeRepository.activeSegments().isEmpty)

        let sessions = try timeRepository.sessions()
        #expect(sessions.first?.endedAt != nil)
    }

    @Test @MainActor
    func segmentEditAndSoftDeleteKeepLedgerConsistent() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Writing", parentID: nil, colorHex: nil, iconName: nil)

        let start = Date(timeIntervalSince1970: 2_000)
        let segment = try timeRepository.addManualSegment(
            taskID: firstTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            note: "Original"
        )

        try timeRepository.updateSegment(
            segmentID: segment.id,
            taskID: secondTask.id,
            startedAt: start.addingTimeInterval(300),
            endedAt: start.addingTimeInterval(2_100),
            note: "Corrected"
        )

        let editedSegments = try timeRepository.segments(from: start, to: start.addingTimeInterval(3_000))
        let updated = try #require(editedSegments.first { $0.id == segment.id })
        #expect(updated.taskID == secondTask.id)
        #expect(updated.startedAt == start.addingTimeInterval(300))
        #expect(updated.endedAt == start.addingTimeInterval(2_100))

        try timeRepository.softDeleteSegment(segmentID: segment.id)
        #expect(try timeRepository.segments(from: start, to: start.addingTimeInterval(3_000)).isEmpty)
    }

    @Test @MainActor
    func segmentRangeQueryUsesExplicitSnapshotDateForActiveSegments() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Active", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 10_000)
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: start, titleSnapshot: task.title)
        let segment = TimeSegment(sessionID: session.id, taskID: task.id, source: .timer, deviceID: "test", startedAt: start, endedAt: nil)
        context.insert(session)
        context.insert(segment)
        try context.save()

        let beforeRange = try timeRepository.segments(
            from: start.addingTimeInterval(600),
            to: start.addingTimeInterval(1_200),
            now: start.addingTimeInterval(300)
        )
        let insideRange = try timeRepository.segments(
            from: start.addingTimeInterval(600),
            to: start.addingTimeInterval(1_200),
            now: start.addingTimeInterval(900)
        )

        #expect(beforeRange.isEmpty)
        #expect(insideRange.map(\.id) == [segment.id])
    }

    @Test @MainActor
    func manualSegmentStoresAndUpdatesSessionNote() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Writing", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 10_000)
        let segment = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_200),
            note: "Initial note"
        )

        var session = try #require(try timeRepository.sessions().first { $0.id == segment.sessionID })
        #expect(session.note == "Initial note")
        #expect(session.titleSnapshot == "Writing")

        try timeRepository.updateSegment(
            segmentID: segment.id,
            taskID: task.id,
            startedAt: start.addingTimeInterval(60),
            endedAt: start.addingTimeInterval(1_500),
            note: "Corrected note"
        )

        session = try #require(try timeRepository.sessions().first { $0.id == segment.sessionID })
        #expect(session.note == "Corrected note")
        #expect(session.startedAt == start.addingTimeInterval(60))
        #expect(session.endedAt == start.addingTimeInterval(1_500))
    }


    @Test @MainActor
    func taskListRollupDurationsIncludeHistoricalDescendantTaskTime() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let parent = try taskRepository.createTask(title: "Parent", parentID: nil, colorHex: nil, iconName: nil)
        let child = try taskRepository.createTask(title: "Child", parentID: parent.id, colorHex: nil, iconName: nil)
        let grandchild = try taskRepository.createTask(title: "Grandchild", parentID: child.id, colorHex: nil, iconName: nil)
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        _ = try timeRepository.addManualSegment(
            taskID: parent.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3_600),
            endedAt: startOfDay.addingTimeInterval(9 * 3_600 + 600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: child.id,
            startedAt: startOfDay.addingTimeInterval(10 * 3_600),
            endedAt: startOfDay.addingTimeInterval(10 * 3_600 + 900),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: grandchild.id,
            startedAt: startOfDay.addingTimeInterval(11 * 3_600),
            endedAt: startOfDay.addingTimeInterval(11 * 3_600 + 300),
            note: nil
        )
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay.addingTimeInterval(-86_400)
        _ = try timeRepository.addManualSegment(
            taskID: child.id,
            startedAt: yesterday.addingTimeInterval(14 * 3_600),
            endedAt: yesterday.addingTimeInterval(14 * 3_600 + 2_400),
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        #expect(store.secondsForTaskToday(parent) == 600)
        #expect(store.secondsForTaskTodayRollup(parent, now: now) == 1_800)
        #expect(store.secondsForTaskTodayRollup(child, now: now) == 1_200)
        #expect(store.secondsForTaskTotal(parent) == 600)
        #expect(store.secondsForTaskTotalRollup(parent, now: now) == 4_200)
        #expect(store.secondsForTaskTotalRollup(child, now: now) == 3_600)
        #expect(store.rollup(for: parent.id)?.workedSeconds == 4_200)
    }
}
