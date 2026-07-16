import Testing
@testable import timetracker

@Suite
struct TimerStopAdmissionPolicyTests {
    private let policy = TimerAdmissionPolicy()

    @Test
    func exactSegmentStopNeverFallsBackToAnotherSegment() {
        let first = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 100,
            startedAt: 100
        )
        let second = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 100,
            startedAt: 200
        )

        let matchingPlan = policy.stopPlan(
            target: .segment(second.segmentID),
            activeSegments: [second, first]
        )
        let missingPlan = policy.stopPlan(
            target: .segment(TimerAdmissionPolicyFixtures.uuid(999)),
            activeSegments: [second, first]
        )

        #expect(matchingPlan.segmentsToStop == [second])
        #expect(missingPlan.isNoOp)
    }

    @Test
    func taskStopReturnsAllMatchingDuplicateSegmentsInStableOrder() {
        let taskID = TimerAdmissionPolicyFixtures.uuid(100)
        let first = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 100,
            startedAt: 200
        )
        let second = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 100,
            startedAt: 100
        )
        let other = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 3,
            taskID: 200,
            startedAt: 50
        )

        let plan = policy.stopPlan(
            target: .task(taskID),
            activeSegments: [first, other, second]
        )

        #expect(plan.segmentsToStop == [second, first])
    }

    @Test
    func currentStopChoosesLatestStartAndHigherSegmentIDForATie() {
        let older = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 9,
            taskID: 100,
            startedAt: 100
        )
        let lowerID = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 200,
            startedAt: 200
        )
        let higherID = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 300,
            startedAt: 200
        )

        let plan = policy.stopPlan(
            target: .current,
            activeSegments: [higherID, older, lowerID]
        )

        #expect(plan.segmentsToStop == [higherID])
    }

    @Test
    func everyStopTargetIsIndependentOfInputOrder() {
        let first = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 100,
            startedAt: 100
        )
        let second = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 100,
            startedAt: 200
        )
        let current = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 3,
            taskID: 200,
            startedAt: 300
        )
        let inputs = [
            [first, second, current],
            [current, second, first],
            [second, first, current],
            [current, first, second]
        ]
        let targets: [TimerStopTarget] = [
            .segment(second.segmentID),
            .task(first.taskID),
            .current
        ]

        for target in targets {
            let plans = inputs.map { policy.stopPlan(target: target, activeSegments: $0) }
            #expect(plans.allSatisfy { $0 == plans[0] })
        }
    }

    @Test
    func repeatedLogicalRowsAreCollapsedAndAppliedStopsBecomeNoOps() {
        let target = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 100,
            startedAt: 100
        )
        let other = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 200,
            startedAt: 200
        )

        let initialPlan = policy.stopPlan(
            target: .task(target.taskID),
            activeSegments: [target, other, target]
        )
        let appliedPlan = policy.stopPlan(
            target: .task(target.taskID),
            activeSegments: [other]
        )

        #expect(initialPlan.segmentsToStop == [target])
        #expect(appliedPlan.isNoOp)
        #expect(policy.stopPlan(
            target: .task(target.taskID),
            activeSegments: [other]
        ) == appliedPlan)
    }
}
