import Foundation
import SwiftData
import Testing
@testable import timetracker

@MainActor
func makeStoreScopedSegmentDraft(
    segmentID: UUID,
    container: ModelContainer
) throws -> SegmentEditorDraft {
    let context = ModelContext(container)
    let timeRepository = SwiftDataTimeTrackingRepository(
        context: context,
        deviceID: "fixture"
    )
    let segment = try #require(
        try timeRepository.segments(ids: [segmentID]).first
    )
    let session = try #require(
        try timeRepository.sessions(ids: [segment.sessionID]).first
    )
    let pomodoroRepository = SwiftDataPomodoroRepository(
        context: context,
        timeRepository: timeRepository,
        deviceID: "fixture"
    )
    let linkedRuns = try pomodoroRepository.activeRuns().filter {
        $0.sessionID == segment.sessionID
    }
    #expect(linkedRuns.count <= 1)
    let run = linkedRuns.first
    return SegmentEditorDraft(
        segment: segment,
        note: session.note ?? "",
        sessionMutationID: session.clientMutationID,
        pomodoroPhase: run.map(PomodoroPhaseToken.init)
    )
}

@MainActor
func makeStoreScopedSegmentCoordinator(
    container: ModelContainer,
    now: Date
) -> StoreScopedSegmentCommandCoordinator {
    StoreScopedSegmentCommandCoordinator(
        container: container,
        writeAuthorization: .isolatedTestHarness,
        deviceID: "coordinator",
        nowProvider: { now }
    )
}

struct StoreScopedSegmentPomodoroFixture {
    let sessionID: UUID
    let activeSegmentID: UUID
    let closedSegmentID: UUID?
    let runID: UUID
    let originalRunMutationID: UUID
}

@MainActor
func insertStoreScopedSegmentPomodoroFixture(
    context: ModelContext,
    task: TaskNode,
    sessionStartedAt: Date,
    activeSegmentStartedAt: Date,
    closedSegmentEnd: Date? = nil,
    focusSeconds: Int = 25 * 60
) throws -> StoreScopedSegmentPomodoroFixture {
    let session = TimeSession(
        taskID: task.id,
        source: .pomodoro,
        deviceID: "fixture",
        startedAt: sessionStartedAt,
        titleSnapshot: task.title
    )
    let closedSegment = closedSegmentEnd.map { end in
        TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .pomodoro,
            deviceID: "fixture",
            startedAt: sessionStartedAt,
            endedAt: end
        )
    }
    let activeSegment = TimeSegment(
        sessionID: session.id,
        taskID: task.id,
        source: .pomodoro,
        deviceID: "fixture",
        startedAt: activeSegmentStartedAt
    )
    let run = PomodoroRun(
        taskID: task.id,
        focus: focusSeconds,
        breakSeconds: 5 * 60,
        targetRounds: 1,
        deviceID: "fixture"
    )
    run.sessionID = session.id
    run.startedAt = sessionStartedAt
    run.state = .focusing
    context.insert(session)
    if let closedSegment {
        context.insert(closedSegment)
    }
    context.insert(activeSegment)
    context.insert(run)
    try context.save()
    return StoreScopedSegmentPomodoroFixture(
        sessionID: session.id,
        activeSegmentID: activeSegment.id,
        closedSegmentID: closedSegment?.id,
        runID: run.id,
        originalRunMutationID: run.clientMutationID
    )
}
