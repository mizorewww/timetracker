import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct AppleHealthReplicaFacadeTests {
    @Test @MainActor
    func timelineSynchronizesThenReadsReplicaAndHideKeepsReplica() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let workoutID = UUID()
        let reader = ReplicaFacadeAppleHealthReader(
            changes: AppleHealthReplicaChangeBatch(
                workouts: [
                    AppleHealthWorkoutSample(
                        id: workoutID,
                        kind: .running,
                        startedAt: now.addingTimeInterval(-1800),
                        endedAt: now.addingTimeInterval(-1200),
                        sourceBundleIdentifier: "test.health"
                    ),
                ],
                deletedWorkoutIDs: [],
                workoutAnchor: Data("workout-1".utf8),
                sleep: [],
                deletedSleepIDs: [],
                sleepAnchor: Data("sleep-1".utf8)
            )
        )
        let repository = try makeAppleHealthReplicaTestRepository()
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthReplicaRepository: repository,
            appleHealthTimelinePreferenceStore:
            TestAppleHealthTimelinePreferenceStore(),
            writeAuthorization: .isolatedTestHarness
        )

        await store.showAppleHealthInTimeline(
            now: now,
            calendar: calendar
        )

        #expect(reader.receivedReplicaAnchors == [.empty])
        #expect(reader.directSampleIntervals.isEmpty)
        #expect(
            store.appleHealthTimelineItems.map(\.id) ==
                [.appleHealthWorkout(workoutID)]
        )
        #expect(try repository.allSamples().recordCount == 1)

        store.hideAppleHealthFromTimeline()

        #expect(store.appleHealthTimelineItems.isEmpty)
        #expect(try repository.allSamples().recordCount == 1)
        #expect(try repository.anchors() == AppleHealthReplicaAnchors(
            workout: Data("workout-1".utf8),
            sleep: Data("sleep-1".utf8)
        ))
    }

    @Test @MainActor
    func pointSampleCommitsWithoutTurningTimelineIntoFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let pointSampleID = UUID()
        let reader = ReplicaFacadeAppleHealthReader(
            changes: AppleHealthReplicaChangeBatch(
                workouts: [
                    AppleHealthWorkoutSample(
                        id: pointSampleID,
                        kind: .walking,
                        startedAt: now.addingTimeInterval(-1200),
                        endedAt: now.addingTimeInterval(-1200),
                        sourceBundleIdentifier: "test.health"
                    ),
                ],
                deletedWorkoutIDs: [],
                workoutAnchor: Data("workout-point".utf8),
                sleep: [],
                deletedSleepIDs: [],
                sleepAnchor: Data("sleep-point".utf8)
            )
        )
        let repository = try makeAppleHealthReplicaTestRepository()
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthReplicaRepository: repository,
            appleHealthTimelinePreferenceStore:
            TestAppleHealthTimelinePreferenceStore(),
            writeAuthorization: .isolatedTestHarness
        )

        await store.showAppleHealthInTimeline(
            now: now,
            calendar: calendar
        )

        let day = try #require(calendar.dateInterval(of: .day, for: now))
        #expect(store.appleHealthTimelineState == .noReadableData(
            interval: DateInterval(start: day.start, end: now),
            refreshedAt: now
        ))
        #expect(store.appleHealthTimelineItems.isEmpty)
        #expect(try repository.allSamples().samples.workouts.map(\.id) ==
            [pointSampleID])
        #expect(try repository.anchors() == AppleHealthReplicaAnchors(
            workout: Data("workout-point".utf8),
            sleep: Data("sleep-point".utf8)
        ))
    }

    @Test @MainActor
    func healthTaskAnalyticsSynchronizesThenReadsReplica() async throws {
        let now = Date(timeIntervalSince1970: 36 * 3600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let definition = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        let workoutID = UUID()
        let reader = ReplicaFacadeAppleHealthReader(
            changes: AppleHealthReplicaChangeBatch(
                workouts: [
                    AppleHealthWorkoutSample(
                        id: workoutID,
                        kind: .running,
                        startedAt: Date(timeIntervalSince1970: 30 * 3600),
                        endedAt: Date(timeIntervalSince1970: 31 * 3600),
                        sourceBundleIdentifier: "test.health"
                    ),
                ],
                deletedWorkoutIDs: [],
                workoutAnchor: Data("workout-1".utf8),
                sleep: [],
                deletedSleepIDs: [],
                sleepAnchor: Data("sleep-1".utf8)
            )
        )
        let repository = try makeAppleHealthReplicaTestRepository()
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthReplicaRepository: repository,
            appleHealthTimelinePreferenceStore:
            TestAppleHealthTimelinePreferenceStore(),
            writeAuthorization: .isolatedTestHarness
        )
        let task = TaskNode(
            title: "Running",
            parentID: nil,
            deviceID: "health"
        )
        task.id = definition.id
        task.path = "Exercise / Running"
        store.tasks = [task]
        let evaluation = AnalyticsRange.today.evaluation(
            referenceDate: now,
            liveNow: now,
            calendar: calendar
        )
        let request = TaskAnalyticsSnapshotRequest(
            taskID: task.id,
            taskIDs: [task.id],
            range: .today,
            evaluation: evaluation,
            revision: 0,
            liveRefreshBucket: nil,
            calendar: calendar
        )

        let snapshot = try #require(
            try await store.loadTaskAnalyticsSnapshot(
                for: request,
                now: now,
                calendar: calendar,
                allowsAuthorizationRequest: true
            )
        )

        #expect(reader.receivedReplicaAnchors == [.empty])
        #expect(reader.directSampleIntervals.isEmpty)
        #expect(snapshot.source == .appleHealth)
        #expect(snapshot.overview.grossSeconds == 3600)
        #expect(snapshot.recentRecords.map(\.id) == [
            .appleHealthWorkout(workoutID),
        ])
    }
}

@MainActor
private final class ReplicaFacadeAppleHealthReader:
    AppleHealthDataReading,
    AppleHealthReplicaChangeReading
{
    let isHealthDataAvailable = true
    let changes: AppleHealthReplicaChangeBatch
    var receivedReplicaAnchors: [AppleHealthReplicaAnchors] = []
    var directSampleIntervals: [DateInterval] = []

    init(changes: AppleHealthReplicaChangeBatch) {
        self.changes = changes
    }

    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus
    {
        .unnecessary
    }

    func requestReadAuthorization() async throws {}

    func samples(
        overlapping interval: DateInterval
    ) async throws -> AppleHealthSampleBatch {
        directSampleIntervals.append(interval)
        return .empty
    }

    func replicaChanges(
        after anchors: AppleHealthReplicaAnchors
    ) async throws -> AppleHealthReplicaChangeBatch {
        receivedReplicaAnchors.append(anchors)
        return changes
    }
}
