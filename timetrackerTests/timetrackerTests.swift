import Foundation
import SwiftData
import Testing
@testable import timetracker

struct TimeTrackerTests {
    @Test @MainActor
    func grossAndWallClockAggregationHandleOverlaps() {
        let taskID = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        let start = Date(timeIntervalSince1970: 1000)

        let first = TimeSegment(
            sessionID: sessionA,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(60 * 60)
        )

        let second = TimeSegment(
            sessionID: sessionB,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start.addingTimeInterval(30 * 60),
            endedAt: start.addingTimeInterval(90 * 60)
        )

        let service = TimeAggregationService()

        #expect(service.totalSeconds(segments: [first, second], mode: .gross) == 7_200)
        #expect(service.totalSeconds(segments: [first, second], mode: .wallClock) == 5_400)
    }

    @Test
    func durationFormattingUsesCompactClockText() {
        #expect(DurationFormatter.compact(4 * 3600 + 35 * 60) == "4h 35m")
        #expect(DurationFormatter.clock(84) == "01:24")
    }

    @Test @MainActor
    func taskMovePreventsCyclesAndUpdatesHierarchy() throws {
        let context = try makeContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")

        let root = try repository.createTask(title: "Root", kind: .project, parentID: nil, colorHex: nil, iconName: nil)
        let child = try repository.createTask(title: "Child", kind: .task, parentID: root.id, colorHex: nil, iconName: nil)

        try repository.moveTask(taskID: root.id, newParentID: child.id, sortOrder: 10)
        #expect((try repository.task(id: root.id))?.parentID == nil)

        try repository.moveTask(taskID: child.id, newParentID: nil, sortOrder: 20)
        let movedTask = try repository.task(id: child.id)
        let moved = try #require(movedTask)
        #expect(moved.parentID == nil)
        #expect(moved.depth == 0)
    }

    @Test @MainActor
    func timerPauseResumeStopUsesSegmentsAsLedger() throws {
        let context = try makeContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Design", kind: .task, parentID: nil, colorHex: nil, iconName: nil)

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

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
