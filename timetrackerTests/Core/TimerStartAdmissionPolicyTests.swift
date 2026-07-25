import Testing
@testable import timetracker

struct TimerStartAdmissionPolicyTests {
    private let policy = TimerAdmissionPolicy()

    @Test
    func exclusiveStartReusesOldestMatchingSegmentAndStopsEveryOtherActiveRow() {
        let taskID = TimerAdmissionPolicyFixtures.uuid(100)
        let survivor = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 100,
            startedAt: 100
        )
        let duplicate = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 100,
            startedAt: 200
        )
        let other = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 3,
            taskID: 200,
            startedAt: 150
        )

        let plan = policy.startPlan(
            taskID: taskID,
            mode: .exclusive,
            activeSegments: [duplicate, other, survivor]
        )

        #expect(plan.decision == .reuse(survivor))
        #expect(plan.segmentsToStop == [other, duplicate])
    }

    @Test
    func parallelStartStillRepairsMatchingDuplicatesButPreservesOtherTasks() {
        let taskID = TimerAdmissionPolicyFixtures.uuid(100)
        let survivor = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 100,
            startedAt: 100
        )
        let duplicate = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 100,
            startedAt: 200
        )
        let other = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 3,
            taskID: 200,
            startedAt: 50
        )

        let plan = policy.startPlan(
            taskID: taskID,
            mode: .parallel,
            activeSegments: [duplicate, other, survivor]
        )

        #expect(plan.decision == .reuse(survivor))
        #expect(plan.segmentsToStop == [duplicate])
    }

    @Test
    func newExclusiveAndParallelStartsDifferOnlyInOtherTaskStops() {
        let taskID = TimerAdmissionPolicyFixtures.uuid(100)
        let older = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 200,
            startedAt: 100
        )
        let newer = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 300,
            startedAt: 200
        )

        let exclusivePlan = policy.startPlan(
            taskID: taskID,
            mode: .exclusive,
            activeSegments: [newer, older]
        )
        let parallelPlan = policy.startPlan(
            taskID: taskID,
            mode: .parallel,
            activeSegments: [newer, older]
        )

        #expect(exclusivePlan.decision == .createNew)
        #expect(exclusivePlan.segmentsToStop == [older, newer])
        #expect(parallelPlan == TimerStartPlan(decision: .createNew, segmentsToStop: []))
    }

    @Test
    func sameTimestampUsesSegmentIDAsStableSurvivorTieBreak() {
        let taskID = TimerAdmissionPolicyFixtures.uuid(100)
        let lowerID = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 100,
            startedAt: 100
        )
        let higherID = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 100,
            startedAt: 100
        )

        let plan = policy.startPlan(
            taskID: taskID,
            mode: .parallel,
            activeSegments: [higherID, lowerID]
        )

        #expect(plan.decision == .reuse(lowerID))
        #expect(plan.segmentsToStop == [higherID])
    }

    @Test
    func replaceAllStopsEveryMatchingSegmentAndCreatesANewOne() {
        let taskID = TimerAdmissionPolicyFixtures.uuid(100)
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
        let other = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 3,
            taskID: 200,
            startedAt: 150
        )

        let parallelPlan = policy.startPlan(
            taskID: taskID,
            mode: .parallel,
            sameTaskBehavior: .replaceAll,
            activeSegments: [second, other, first]
        )
        let exclusivePlan = policy.startPlan(
            taskID: taskID,
            mode: .exclusive,
            sameTaskBehavior: .replaceAll,
            activeSegments: [second, other, first]
        )

        #expect(parallelPlan == TimerStartPlan(
            decision: .createNew,
            segmentsToStop: [first, second]
        ))
        #expect(exclusivePlan == TimerStartPlan(
            decision: .createNew,
            segmentsToStop: [first, other, second]
        ))
    }

    @Test
    func startPlanIsIndependentOfInputOrderAndDuplicateLogicalRows() {
        let taskID = TimerAdmissionPolicyFixtures.uuid(100)
        let survivor = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 100,
            startedAt: 100
        )
        let duplicate = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 100,
            startedAt: 200
        )
        let other = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 3,
            taskID: 200,
            startedAt: 150
        )
        let inputs = [
            [survivor, duplicate, other, duplicate],
            [other, duplicate, survivor, duplicate],
            [duplicate, survivor, duplicate, other],
            [duplicate, other, duplicate, survivor],
        ]

        let plans = inputs.map {
            policy.startPlan(taskID: taskID, mode: .exclusive, activeSegments: $0)
        }

        #expect(plans.allSatisfy { $0 == plans[0] })
        #expect(plans[0].decision == .reuse(survivor))
        #expect(plans[0].segmentsToStop == [other, duplicate])
    }

    @Test
    func applyingDuplicateCleanupConvergesToAnIdempotentReusePlan() {
        let taskID = TimerAdmissionPolicyFixtures.uuid(100)
        let survivor = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 1,
            taskID: 100,
            startedAt: 100
        )
        let duplicate = TimerAdmissionPolicyFixtures.snapshot(
            segmentID: 2,
            taskID: 100,
            startedAt: 200
        )

        let initialPlan = policy.startPlan(
            taskID: taskID,
            mode: .parallel,
            activeSegments: [duplicate, survivor]
        )
        let convergedPlan = policy.startPlan(
            taskID: taskID,
            mode: .parallel,
            activeSegments: [survivor]
        )

        #expect(initialPlan.segmentsToStop == [duplicate])
        #expect(convergedPlan == TimerStartPlan(decision: .reuse(survivor), segmentsToStop: []))
        #expect(policy.startPlan(
            taskID: taskID,
            mode: .parallel,
            activeSegments: [survivor]
        ) == convergedPlan)
    }
}
