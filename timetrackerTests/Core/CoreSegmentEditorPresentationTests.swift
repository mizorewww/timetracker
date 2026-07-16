import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct CoreSegmentEditorPresentationTests {
    @Test
    func deletionImpactMatchesCanonicalUserVisibleEffect() {
        let taskID = UUID()
        let sessionID = UUID()
        let startedAt = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let historical = TimeSegment(
            sessionID: sessionID,
            taskID: taskID,
            source: .manual,
            deviceID: "test",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60)
        )
        let running = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: startedAt
        )
        let focus = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .pomodoro,
            deviceID: "test",
            startedAt: startedAt
        )
        let run = PomodoroRun(
            taskID: taskID,
            deviceID: "test"
        )
        run.sessionID = focus.sessionID
        run.startedAt = startedAt
        run.state = .focusing

        let historicalImpact = SegmentDeletionImpact(
            baseline: SegmentEditorDraftBaseline(segment: historical)
        )
        let runningImpact = SegmentDeletionImpact(
            baseline: SegmentEditorDraftBaseline(segment: running)
        )
        let focusImpact = SegmentDeletionImpact(
            baseline: SegmentEditorDraftBaseline(
                segment: focus,
                pomodoroPhase: PomodoroPhaseToken(run: run)
            )
        )

        #expect(historicalImpact == .historicalRecord)
        #expect(runningImpact == .runningTimer)
        #expect(focusImpact == .activeFocusSession)
        #expect(historicalImpact.confirmationMessage != runningImpact.confirmationMessage)
        #expect(runningImpact.confirmationMessage != focusImpact.confirmationMessage)
        #expect(historicalImpact.confirmationActionTitle != focusImpact.confirmationActionTitle)
    }

    @Test
    func onlyVersionFailuresBecomeEditorRecoveryStates() {
        #expect(SegmentEditorRecoveryError(SegmentMutationError.staleDraft) == .stale)
        #expect(
            SegmentEditorRecoveryError(SegmentMutationError.inconsistentSession)
                == .inconsistent
        )
        #expect(
            SegmentEditorRecoveryError(SegmentMutationError.activeTimerStartInFuture)
                == nil
        )
        #expect(
            SegmentEditorRecoveryError(TimeTrackingRepositoryError.invalidTimeRange)
                == nil
        )
        #expect(
            SegmentEditorRecoveryError.stale.title !=
                SegmentEditorRecoveryError.inconsistent.title
        )
    }
}
