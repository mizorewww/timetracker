import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct CommittedMutationSystemSurfaceMaterializerTests {
    @Test
    func materializeProjectsTheCommittedRunningTimerToEverySurface() async throws {
        let context = try makeTestContext()
        let calendar = utcCalendar()
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )))
        let task = TaskNode(title: "Running task", parentID: nil, deviceID: "fixture")
        let session = TimeSession(
            taskID: task.id,
            source: .timer,
            deviceID: "fixture",
            startedAt: now.addingTimeInterval(-600)
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "fixture",
            startedAt: now.addingTimeInterval(-600)
        )
        context.insert(task)
        context.insert(session)
        context.insert(segment)
        try context.save()

        let checkpoints = CheckpointRecorder()
        let materialization = try await CommittedMutationSystemSurfaceMaterializer(
            modelContainer: context.container
        )
        .materialize(now: now, calendar: calendar) { checkpoint in
            checkpoints.record(checkpoint)
        }

        #expect(checkpoints.values == [
            .beforeCommittedFactRead,
            .afterCommittedFactRead,
            .afterMaterialization,
        ])
        #expect(materialization.generatedAt == now)
        #expect(materialization.widgetSnapshot.generatedAt == now)
        #expect(materialization.widgetSnapshot.activeTimers.map(\.taskID) == [task.id])
        #expect(materialization.widgetSnapshot.activeTimers.map(\.title) == ["Running task"])
        #expect(materialization.widgetSnapshot.todayGrossSeconds == 600)
        #expect(materialization.widgetSnapshot.todayWallSeconds == 600)
        #expect(materialization.watchSnapshot.activeTimers.map(\.taskID) == [task.id])
        let liveActivity = materialization.liveActivity
        guard case let .active(state) = liveActivity else {
            Issue.record("A committed running segment must project an active Live Activity")
            return
        }
        #expect(state.segmentID == segment.id.uuidString)
        #expect(state.taskTitle == "Running task")
        #expect(state.startedAt == segment.startedAt)
    }

    @Test
    func materializeIgnoresSegmentsWhoseSessionDisagreesWithTheCommittedTask() async throws {
        let context = try makeTestContext()
        let calendar = utcCalendar()
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )))
        let task = TaskNode(title: "Owning task", parentID: nil, deviceID: "fixture")
        let otherTask = TaskNode(title: "Other task", parentID: nil, deviceID: "fixture")
        let session = TimeSession(
            taskID: task.id,
            source: .timer,
            deviceID: "fixture",
            startedAt: now.addingTimeInterval(-600)
        )
        let readableSegment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "fixture",
            startedAt: now.addingTimeInterval(-600)
        )
        let sessionMismatchedSegment = TimeSegment(
            sessionID: session.id,
            taskID: otherTask.id,
            source: .timer,
            deviceID: "fixture",
            startedAt: now.addingTimeInterval(-300)
        )
        let sessionlessSegment = TimeSegment(
            sessionID: UUID(),
            taskID: task.id,
            source: .timer,
            deviceID: "fixture",
            startedAt: now.addingTimeInterval(-300)
        )
        context.insert(task)
        context.insert(otherTask)
        context.insert(session)
        context.insert(readableSegment)
        context.insert(sessionMismatchedSegment)
        context.insert(sessionlessSegment)
        try context.save()

        let materialization = try await CommittedMutationSystemSurfaceMaterializer(
            modelContainer: context.container
        )
        .materialize(now: now, calendar: calendar)

        #expect(materialization.widgetSnapshot.activeTimers.map(\.id) == [readableSegment.id])
        #expect(materialization.widgetSnapshot.todayGrossSeconds == 600)
        let liveActivity = materialization.liveActivity
        guard case let .active(state) = liveActivity else {
            Issue.record("The readable segment must remain the projected timer")
            return
        }
        #expect(state.segmentID == readableSegment.id.uuidString)
    }

    @Test
    func emptyStoreMaterializesInactiveSurfaces() async throws {
        let context = try makeTestContext()
        let calendar = utcCalendar()
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 20,
            hour: 12
        )))

        let materialization = try await CommittedMutationSystemSurfaceMaterializer(
            modelContainer: context.container
        )
        .materialize(now: now, calendar: calendar)

        #expect(materialization.generatedAt == now)
        #expect(materialization.widgetSnapshot.activeTimers.isEmpty)
        #expect(materialization.widgetSnapshot.todayGrossSeconds == 0)
        #expect(materialization.widgetSnapshot.todayWallSeconds == 0)
        #expect(materialization.watchSnapshot.activeTimers.isEmpty)
        #expect(materialization.liveActivity == .inactive)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private final class CheckpointRecorder: @unchecked Sendable {
        private(set) var values:
            [CommittedMutationSystemSurfaceMaterializationCheckpoint] = []

        func record(
            _ checkpoint: CommittedMutationSystemSurfaceMaterializationCheckpoint
        ) {
            values.append(checkpoint)
        }
    }
}
