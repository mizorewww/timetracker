import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct AppleHealthTaskAnalyticsTests {
    @Test
    func compactMonthAxisKeepsFiveEvenlySpacedReadableLabels() {
        #expect(
            DailyTimeSeriesXAxisPolicy.labelIndices(
                pointCount: 31,
                maximumLabelCount: 5
            ) == [0, 7, 15, 22, 30]
        )
        #expect(
            DailyTimeSeriesXAxisPolicy.labelIndices(
                pointCount: 4,
                maximumLabelCount: 5
            ) == [0, 1, 2, 3]
        )
        #expect(
            DailyTimeSeriesXAxisPolicy.labelIndices(
                pointCount: 0,
                maximumLabelCount: 5
            ).isEmpty
        )
    }

    @Test
    func catalogResolvesOnlyExactGeneratedTaskIDsAndIDsExposeNamespace() throws {
        for role in AppleHealthTaskCatalog.allRoles {
            let taskID = AppleHealthTaskCatalog.taskDefinition(for: role).id
            #expect(AppleHealthTaskCatalog.taskRole(for: taskID) == role)
        }
        #expect(AppleHealthTaskCatalog.taskRole(for: UUID()) == nil)

        let workoutID = try #require(
            UUID(
                uuidString: "D0410000-0000-4000-8000-000000000001"
            )
        )
        let timelineID = TimelineEntryID.appleHealthWorkout(workoutID)
        #expect(timelineID.namespace == "appleHealthWorkout")
        #expect(timelineID.uuid == workoutID)
        #expect(
            "task.detail.history.\(timelineID.namespacedKey)"
                == "task.detail.history.appleHealthWorkout.D0410000-0000-4000-8000-000000000001"
        )
    }

    @Test
    func projectionBuildsGrossWallComparisonRhythmAndNamespacedRecentRecords()
        throws {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 36 * 3_600)
        let definition = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        let request = request(
            taskID: definition.id,
            range: .today,
            now: now,
            calendar: calendar
        )
        let previousMatchedID = try fixedID(1)
        let previousUnmatchedID = try fixedID(2)
        let currentEarlyID = try fixedID(3)
        let currentLateID = try fixedID(4)
        let snapshot = AppleHealthTaskAnalyticsProjectionService().snapshot(
            role: .workout(.running),
            taskID: definition.id,
            title: "Running",
            path: "Exercise / Running",
            batch: AppleHealthSampleBatch(
                workouts: [
                    workout(
                        id: previousMatchedID,
                        kind: .running,
                        start: 3_600,
                        end: 7_200
                    ),
                    workout(
                        id: previousUnmatchedID,
                        kind: .running,
                        start: 13 * 3_600,
                        end: 14 * 3_600
                    ),
                    workout(
                        id: currentEarlyID,
                        kind: .running,
                        start: 32 * 3_600,
                        end: 34 * 3_600
                    ),
                    workout(
                        id: currentLateID,
                        kind: .running,
                        start: 33 * 3_600,
                        end: 35 * 3_600
                    ),
                    workout(
                        id: try fixedID(5),
                        kind: .walking,
                        start: 34 * 3_600,
                        end: 35 * 3_600
                    ),
                ],
                sleep: []
            ),
            request: request,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.source == .appleHealth)
        #expect(snapshot.overview.grossSeconds == 4 * 3_600)
        #expect(snapshot.overview.wallSeconds == 3 * 3_600)
        #expect(snapshot.overview.overlapSeconds == 3_600)
        #expect(snapshot.comparison.previousGrossSeconds == 3_600)
        #expect(snapshot.comparison.previousWallSeconds == 3_600)
        #expect(snapshot.directSeconds == snapshot.overview.grossSeconds)
        #expect(snapshot.descendantSeconds == 0)
        #expect(snapshot.childBreakdown.isEmpty)
        #expect(snapshot.rhythm.activeDayCount == 1)
        #expect(snapshot.rhythm.peakHour == 9)
        #expect(snapshot.rhythm.peakHourSeconds == 2 * 3_600)
        #expect(snapshot.rhythm.segmentCount == 2)
        #expect(snapshot.quality.overlapRatio == 0.25)
        #expect(snapshot.quality.switchCount == 0)
        #expect(snapshot.daily.count == 1)
        #expect(snapshot.daily.first?.grossSeconds == 4 * 3_600)
        #expect(snapshot.daily.first?.wallSeconds == 3 * 3_600)
        #expect(snapshot.recentRecords.map(\.id) == [
            .appleHealthWorkout(currentLateID),
            .appleHealthWorkout(currentEarlyID),
        ])
    }

    @Test
    func historicalWeekUsesCompleteSelectedIntervalAndExcludesLiveEvidence()
        throws {
        let calendar = utcCalendar()
        let liveNow = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 23,
                    hour: 12
                )
            )
        )
        let historicalReference = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 6,
                    hour: 12
                )
            )
        )
        let definition = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        let task = TaskNode(
            title: "Running",
            parentID: nil,
            deviceID: "health"
        )
        task.id = definition.id
        task.path = "Exercise / Running"
        let store = healthStore(
            task: task,
            reader: TaskAnalyticsAppleHealthReader(batch: .empty)
        )
        let evaluation = AnalyticsRange.week.evaluation(
            referenceDate: historicalReference,
            liveNow: liveNow,
            calendar: calendar
        )
        let request = store.taskAnalyticsSnapshotRequest(
            for: task,
            range: .week,
            referenceDate: historicalReference,
            liveNow: liveNow,
            calendar: calendar
        )
        let service = AppleHealthTaskAnalyticsProjectionService()
        let plan = service.queryPlan(
            for: request,
            now: liveNow,
            calendar: calendar
        )

        #expect(request.evaluationKey.interval == evaluation.interval)
        #expect(evaluation.cutoff == evaluation.interval.end)
        #expect(plan.comparisonWindow.current == evaluation.interval)
        #expect(plan.comparisonWindow.basis == .completePeriods)
        #expect(
            plan.projectionInterval
                == DateInterval(
                    start: plan.comparisonWindow.previous.start,
                    end: evaluation.interval.end
                )
        )
        #expect(
            plan.queryInterval
                == DateInterval(
                    start: plan.comparisonWindow.previous.start
                        .addingTimeInterval(
                            -AppleHealthSleepEpisodePolicy.queryContextDuration
                        ),
                    end: evaluation.interval.end
                )
        )

        let previousID = try fixedID(60)
        let historicalEarlyID = try fixedID(61)
        let historicalLateID = try fixedID(62)
        let liveID = try fixedID(63)
        let historicalStart = evaluation.interval.start
        let previousStart = plan.comparisonWindow.previous.start
        let snapshot = service.snapshot(
            role: .workout(.running),
            taskID: definition.id,
            title: "Running",
            path: "Exercise / Running",
            batch: AppleHealthSampleBatch(
                workouts: [
                    workout(
                        id: previousID,
                        kind: .running,
                        start: previousStart.addingTimeInterval(9 * 3_600)
                            .timeIntervalSince1970,
                        end: previousStart.addingTimeInterval(10 * 3_600)
                            .timeIntervalSince1970
                    ),
                    workout(
                        id: historicalEarlyID,
                        kind: .running,
                        start: historicalStart.addingTimeInterval(9 * 3_600)
                            .timeIntervalSince1970,
                        end: historicalStart.addingTimeInterval(11 * 3_600)
                            .timeIntervalSince1970
                    ),
                    workout(
                        id: historicalLateID,
                        kind: .running,
                        start: historicalStart.addingTimeInterval(10 * 3_600)
                            .timeIntervalSince1970,
                        end: historicalStart.addingTimeInterval(12 * 3_600)
                            .timeIntervalSince1970
                    ),
                    workout(
                        id: liveID,
                        kind: .running,
                        start: liveNow.addingTimeInterval(-2 * 3_600)
                            .timeIntervalSince1970,
                        end: liveNow.addingTimeInterval(-3_600)
                            .timeIntervalSince1970
                    ),
                ],
                sleep: []
            ),
            request: request,
            now: liveNow,
            calendar: calendar
        )

        #expect(snapshot.overview.grossSeconds == 4 * 3_600)
        #expect(snapshot.overview.wallSeconds == 3 * 3_600)
        #expect(snapshot.comparison.previousGrossSeconds == 3_600)
        #expect(snapshot.comparison.previousWallSeconds == 3_600)
        #expect(snapshot.recentRecords.map(\.id) == [
            .appleHealthWorkout(historicalLateID),
            .appleHealthWorkout(historicalEarlyID),
        ])
        #expect(snapshot.recentRecords.contains { $0.id == .appleHealthWorkout(liveID) } == false)
    }

    @Test
    func queryIncludesPreviousPeriodAndSleepContextWhileEmptyHealthStaysTyped()
        throws {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 36 * 3_600)
        let definition = AppleHealthTaskCatalog.taskDefinition(for: .sleep)
        let request = request(
            taskID: definition.id,
            range: .today,
            now: now,
            calendar: calendar
        )
        let service = AppleHealthTaskAnalyticsProjectionService()
        let plan = service.queryPlan(
            for: request,
            now: now,
            calendar: calendar
        )

        #expect(plan.comparisonWindow.previous.start == Date(timeIntervalSince1970: 0))
        #expect(plan.comparisonWindow.previous.end == Date(timeIntervalSince1970: 12 * 3_600))
        #expect(plan.comparisonWindow.current.start == Date(timeIntervalSince1970: 24 * 3_600))
        #expect(plan.comparisonWindow.current.end == now)
        #expect(
            plan.queryInterval.start
                == Date(
                    timeIntervalSince1970:
                        -AppleHealthSleepEpisodePolicy.queryContextDuration
                )
        )
        #expect(plan.queryInterval.end == now)

        let snapshot = service.snapshot(
            role: .sleep,
            taskID: definition.id,
            title: "Sleep",
            path: "Daily / Sleep",
            batch: .empty,
            request: request,
            now: now,
            calendar: calendar
        )
        #expect(snapshot.source == .appleHealth)
        #expect(snapshot.overview.grossSeconds == 0)
        #expect(snapshot.directSeconds == 0)
        #expect(snapshot.daily.count == 1)
        #expect(snapshot.daily.first?.grossSeconds == 0)
        #expect(snapshot.recentRecords.isEmpty)
    }

    @Test
    func sleepComparisonUsesContextWhileCurrentRecordKeepsFullEpisode()
        throws {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 36 * 3_600)
        let definition = AppleHealthTaskCatalog.taskDefinition(for: .sleep)
        let request = request(
            taskID: definition.id,
            range: .today,
            now: now,
            calendar: calendar
        )
        let previousAnchorID = try fixedID(20)
        let currentAnchorID = try fixedID(21)
        let snapshot = AppleHealthTaskAnalyticsProjectionService().snapshot(
            role: .sleep,
            taskID: definition.id,
            title: "Sleep",
            path: "Daily / Sleep",
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: [
                    AppleHealthSleepSample(
                        id: previousAnchorID,
                        stage: .asleepCore,
                        startedAt: Date(timeIntervalSince1970: -3_600),
                        endedAt: Date(timeIntervalSince1970: 3_600),
                        sourceBundleIdentifier: "test.sleep.previous",
                        sourceProductType: "watch"
                    ),
                    AppleHealthSleepSample(
                        id: currentAnchorID,
                        stage: .asleepCore,
                        startedAt: Date(
                            timeIntervalSince1970: 23 * 3_600
                        ),
                        endedAt: Date(
                            timeIntervalSince1970: 25 * 3_600
                        ),
                        sourceBundleIdentifier: "test.sleep.current",
                        sourceProductType: "watch"
                    ),
                ]
            ),
            request: request,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.comparison.previousGrossSeconds == 3_600)
        #expect(snapshot.comparison.previousWallSeconds == 3_600)
        #expect(snapshot.overview.grossSeconds == 3_600)
        #expect(snapshot.recentRecords.map(\.id) == [
            .appleHealthSleep(currentAnchorID),
        ])
        #expect(
            snapshot.recentRecords.first?.startedAt
                == Date(timeIntervalSince1970: 23 * 3_600)
        )
        #expect(
            snapshot.recentRecords.first?.endedAt
                == Date(timeIntervalSince1970: 25 * 3_600)
        )
        #expect(snapshot.recentRecords.first?.durationSeconds == 2 * 3_600)
    }

    @Test
    func sleepRecordDurationExcludesAwakeEvidenceInsideEpisodeEnvelope()
        throws {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 36 * 3_600)
        let definition = AppleHealthTaskCatalog.taskDefinition(for: .sleep)
        let request = request(
            taskID: definition.id,
            range: .today,
            now: now,
            calendar: calendar
        )
        let coreID = try fixedID(30)
        let awakeID = try fixedID(31)
        let deepID = try fixedID(32)
        let source = "test.sleep.awake-gap"
        let product = "watch"
        let snapshot = AppleHealthTaskAnalyticsProjectionService().snapshot(
            role: .sleep,
            taskID: definition.id,
            title: "Sleep",
            path: "Daily / Sleep",
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: [
                    AppleHealthSleepSample(
                        id: coreID,
                        stage: .asleepCore,
                        startedAt: Date(
                            timeIntervalSince1970: 24 * 3_600
                        ),
                        endedAt: Date(
                            timeIntervalSince1970: 25 * 3_600
                        ),
                        sourceBundleIdentifier: source,
                        sourceProductType: product
                    ),
                    AppleHealthSleepSample(
                        id: awakeID,
                        stage: .awake,
                        startedAt: Date(
                            timeIntervalSince1970: 25 * 3_600
                        ),
                        endedAt: Date(
                            timeIntervalSince1970: 25 * 3_600 + 20 * 60
                        ),
                        sourceBundleIdentifier: source,
                        sourceProductType: product
                    ),
                    AppleHealthSleepSample(
                        id: deepID,
                        stage: .asleepDeep,
                        startedAt: Date(
                            timeIntervalSince1970: 25 * 3_600 + 20 * 60
                        ),
                        endedAt: Date(
                            timeIntervalSince1970: 26 * 3_600 + 20 * 60
                        ),
                        sourceBundleIdentifier: source,
                        sourceProductType: product
                    ),
                ]
            ),
            request: request,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.overview.grossSeconds == 2 * 3_600)
        let record = try #require(snapshot.recentRecords.first)
        let endedAt = try #require(record.endedAt)
        #expect(record.id == .appleHealthSleep(coreID))
        #expect(
            endedAt.timeIntervalSince(record.startedAt)
                == 2 * 3_600 + 20 * 60
        )
        #expect(record.durationSeconds == 2 * 3_600)
        #expect(
            record.displayDurationSeconds(
                source: .appleHealth,
                now: now
            ) == 2 * 3_600
        )
        #expect(
            record.displayDurationSeconds(
                source: .tracked,
                now: now
            ) == 2 * 3_600 + 20 * 60
        )
    }

    @Test
    func recentHealthRecordsAreDescendingAndCappedAtEight() throws {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 36 * 3_600)
        let definition = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        let request = request(
            taskID: definition.id,
            range: .today,
            now: now,
            calendar: calendar
        )
        let ids = try (1...10).map(fixedID)
        let workouts = ids.enumerated().map { index, id in
            workout(
                id: id,
                kind: .running,
                start: 24 * 3_600 + Double(index) * 3_600,
                end: 24 * 3_600 + Double(index) * 3_600 + 600
            )
        }
        let snapshot = AppleHealthTaskAnalyticsProjectionService().snapshot(
            role: .workout(.running),
            taskID: definition.id,
            title: "Running",
            path: "Exercise / Running",
            batch: AppleHealthSampleBatch(workouts: workouts, sleep: []),
            request: request,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.recentRecords.count == 8)
        #expect(snapshot.recentRecords.first?.id == .appleHealthWorkout(ids[9]))
        #expect(snapshot.recentRecords.last?.id == .appleHealthWorkout(ids[2]))
    }

    @Test
    func facadeForwardsOrdinaryTasksWithoutConsultingHealthAvailability()
        async throws {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 36 * 3_600)
        let task = TaskNode(
            title: "Ordinary",
            parentID: nil,
            deviceID: "test"
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: UnavailableAppleHealthDataReader(),
            appleHealthTimelinePreferenceStore:
                TestAppleHealthTimelinePreferenceStore(),
            writeAuthorization: .isolatedTestHarness
        )
        store.tasks = [task]
        let request = request(
            taskID: task.id,
            range: .today,
            now: now,
            calendar: calendar
        )

        let snapshot = try #require(
            try await store.loadTaskAnalyticsSnapshot(
                for: request,
                now: now,
                calendar: calendar,
                allowsAuthorizationRequest: false
            )
        )
        #expect(snapshot.source == .tracked)
    }

    @Test
    func facadeAvoidsAnUnpromptedSheetButExplicitDetailAuthorizesAndQueries()
        async throws {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 36 * 3_600)
        let definition = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        let task = TaskNode(
            title: "Running",
            parentID: nil,
            deviceID: "health"
        )
        task.id = definition.id
        task.path = "Exercise / Running"
        let reader = TaskAnalyticsAppleHealthReader(
            batch: .empty,
            requestStatus: .shouldRequest
        )
        let store = healthStore(task: task, reader: reader)
        let request = request(
            taskID: task.id,
            range: .today,
            now: now,
            calendar: calendar
        )

        let avoided = try #require(
            try await store.loadTaskAnalyticsSnapshot(
                for: request,
                now: now,
                calendar: calendar,
                allowsAuthorizationRequest: false
            )
        )
        #expect(avoided.source == .appleHealth)
        #expect(avoided.overview.grossSeconds == 0)
        #expect(reader.authorizationStatusCount == 1)
        #expect(reader.authorizationRequestCount == 0)
        #expect(reader.sampleIntervals.isEmpty)

        _ = try await store.loadTaskAnalyticsSnapshot(
            for: request,
            now: now,
            calendar: calendar,
            allowsAuthorizationRequest: true
        )
        #expect(reader.authorizationRequestCount == 1)
        #expect(reader.sampleIntervals.count == 1)
        #expect(
            reader.sampleIntervals.first?.start
                == Date(
                    timeIntervalSince1970:
                        -AppleHealthSleepEpisodePolicy.queryContextDuration
                )
        )
        #expect(reader.sampleIntervals.first?.end == now)
    }

    @Test
    func facadePropagatesUnavailableAndCancellation() async throws {
        let calendar = utcCalendar()
        let now = Date(timeIntervalSince1970: 36 * 3_600)
        let definition = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        let unavailableTask = TaskNode(
            title: "Running",
            parentID: nil,
            deviceID: "health"
        )
        unavailableTask.id = definition.id
        let unavailableStore = healthStore(
            task: unavailableTask,
            reader: TaskAnalyticsAppleHealthReader(
                isHealthDataAvailable: false,
                batch: .empty
            )
        )
        let request = request(
            taskID: definition.id,
            range: .today,
            now: now,
            calendar: calendar
        )
        await #expect(throws: AppleHealthReadError.unavailable) {
            _ = try await unavailableStore.loadTaskAnalyticsSnapshot(
                for: request,
                now: now,
                calendar: calendar,
                allowsAuthorizationRequest: true
            )
        }

        let reader = TaskAnalyticsAppleHealthReader(
            batch: .empty,
            suspendsSamples: true
        )
        let cancellableTask = TaskNode(
            title: "Running",
            parentID: nil,
            deviceID: "health"
        )
        cancellableTask.id = definition.id
        let store = healthStore(task: cancellableTask, reader: reader)
        let load = Task { @MainActor in
            try await store.loadTaskAnalyticsSnapshot(
                for: request,
                now: now,
                calendar: calendar,
                allowsAuthorizationRequest: true
            )
        }
        for _ in 0..<100 where reader.sampleIntervals.isEmpty {
            await Task.yield()
        }
        #expect(reader.sampleIntervals.count == 1)
        load.cancel()
        do {
            _ = try await load.value
            Issue.record("Expected the Health analytics load to cancel")
        } catch is CancellationError {
            // Expected: cancellation must not be converted into an empty snapshot.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
        #expect(reader.sampleCancellationCount == 1)
    }

    private func healthStore(
        task: TaskNode,
        reader: TaskAnalyticsAppleHealthReader
    ) -> TimeTrackerStore {
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore:
                TestAppleHealthTimelinePreferenceStore(),
            writeAuthorization: .isolatedTestHarness
        )
        store.tasks = [task]
        return store
    }

    private func request(
        taskID: UUID,
        range: AnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> TaskAnalyticsSnapshotRequest {
        let evaluation = range.evaluation(
            referenceDate: now,
            liveNow: now,
            calendar: calendar
        )
        return TaskAnalyticsSnapshotRequest(
            taskID: taskID,
            taskIDs: [taskID],
            range: range,
            evaluation: evaluation,
            revision: 0,
            liveRefreshBucket: nil,
            calendar: calendar
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func workout(
        id: UUID,
        kind: AppleHealthWorkoutKind,
        start: TimeInterval,
        end: TimeInterval
    ) -> AppleHealthWorkoutSample {
        AppleHealthWorkoutSample(
            id: id,
            kind: kind,
            startedAt: Date(timeIntervalSince1970: start),
            endedAt: Date(timeIntervalSince1970: end),
            sourceBundleIdentifier: "test.health"
        )
    }

    private func fixedID(_ suffix: Int) throws -> UUID {
        try #require(
            UUID(
                uuidString: String(
                    format: "D0410000-0000-4000-8000-%012d",
                    suffix
                )
            )
        )
    }
}

@MainActor
private final class TaskAnalyticsAppleHealthReader: AppleHealthDataReading {
    let isHealthDataAvailable: Bool
    var batch: AppleHealthSampleBatch
    var requestStatus: AppleHealthAuthorizationRequestStatus
    var authorizationStatusCount = 0
    var authorizationRequestCount = 0
    var sampleIntervals: [DateInterval] = []
    var sampleCancellationCount = 0
    var suspendsSamples: Bool

    init(
        isHealthDataAvailable: Bool = true,
        batch: AppleHealthSampleBatch,
        requestStatus: AppleHealthAuthorizationRequestStatus = .unnecessary,
        suspendsSamples: Bool = false
    ) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.batch = batch
        self.requestStatus = requestStatus
        self.suspendsSamples = suspendsSamples
    }

    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus {
        authorizationStatusCount += 1
        return requestStatus
    }

    func requestReadAuthorization() async throws {
        authorizationRequestCount += 1
    }

    func samples(
        overlapping interval: DateInterval
    ) async throws -> AppleHealthSampleBatch {
        sampleIntervals.append(interval)
        do {
            while suspendsSamples {
                try Task.checkCancellation()
                await Task.yield()
            }
        } catch {
            sampleCancellationCount += 1
            throw error
        }
        return batch
    }
}
