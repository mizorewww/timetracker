import Foundation
import Testing
@testable import timetracker

@Suite
struct TimerRapidRestartPolicyTests {
    private let policy = TimerRapidRestartPolicy()
    private let taskID = UUID()
    private let start = Date(timeIntervalSinceReferenceDate: 10_000)

    @Test
    func gapMustBeNonnegativeAndStrictlyLessThanOneMinute() {
        let end = start.addingTimeInterval(120)

        #expect(shouldCoalesce(previousEnd: end, nextStart: end))
        #expect(
            shouldCoalesce(
                previousEnd: end,
                nextStart: end.addingTimeInterval(59.999)
            )
        )
        #expect(
            shouldCoalesce(
                previousEnd: end,
                nextStart: end.addingTimeInterval(60)
            ) == false
        )
        #expect(
            shouldCoalesce(
                previousEnd: end,
                nextStart: end.addingTimeInterval(-0.001)
            ) == false
        )
    }

    @Test
    func everyOrdinaryTimerSourceCanContinueEveryOtherSource() {
        let sources: [TimeSessionSource] = [
            .timer,
            .shortcut,
            .watch,
            .widget,
            .liveActivity,
        ]
        let end = start.addingTimeInterval(120)

        for previousSource in sources {
            for nextSource in sources {
                #expect(
                    policy.shouldCoalesce(
                        previousTaskID: taskID,
                        previousSource: previousSource,
                        previousStartedAt: start,
                        previousEndedAt: end,
                        nextTaskID: taskID,
                        nextSource: nextSource,
                        nextStartedAt: end.addingTimeInterval(30)
                    )
                )
            }
        }
    }

    @Test
    func explicitRecordSourcesNeverJoinAnOrdinaryTimer() {
        let explicitSources: [TimeSessionSource] = [
            .manual,
            .pomodoro,
            .importCalendar,
        ]
        let end = start.addingTimeInterval(120)

        for source in explicitSources {
            #expect(
                policy.shouldCoalesce(
                    previousTaskID: taskID,
                    previousSource: source,
                    previousStartedAt: start,
                    previousEndedAt: end,
                    nextTaskID: taskID,
                    nextSource: .timer,
                    nextStartedAt: end.addingTimeInterval(30)
                ) == false
            )
            #expect(
                policy.shouldCoalesce(
                    previousTaskID: taskID,
                    previousSource: .timer,
                    previousStartedAt: start,
                    previousEndedAt: end,
                    nextTaskID: taskID,
                    nextSource: source,
                    nextStartedAt: end.addingTimeInterval(30)
                ) == false
            )
        }
    }

    @Test
    func taskIdentityAndPositivePredecessorDurationAreRequired() {
        let end = start.addingTimeInterval(120)

        #expect(
            policy.shouldCoalesce(
                previousTaskID: taskID,
                previousSource: .timer,
                previousStartedAt: start,
                previousEndedAt: end,
                nextTaskID: UUID(),
                nextSource: .timer,
                nextStartedAt: end.addingTimeInterval(30)
            ) == false
        )
        #expect(
            policy.shouldCoalesce(
                previousTaskID: taskID,
                previousSource: .timer,
                previousStartedAt: start,
                previousEndedAt: start,
                nextTaskID: taskID,
                nextSource: .timer,
                nextStartedAt: start.addingTimeInterval(30)
            ) == false
        )
    }

    private func shouldCoalesce(
        previousEnd: Date,
        nextStart: Date
    ) -> Bool {
        policy.shouldCoalesce(
            previousTaskID: taskID,
            previousSource: .timer,
            previousStartedAt: start,
            previousEndedAt: previousEnd,
            nextTaskID: taskID,
            nextSource: .timer,
            nextStartedAt: nextStart
        )
    }
}
