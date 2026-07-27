#if DEBUG && os(iOS)
import Foundation

/// Deterministic, in-memory Health samples for UI verification. The factory
/// requires a UI-test launch plus an explicit argument or environment signal,
/// so ordinary Debug launches keep using HealthKit and Release builds contain
/// no fixture path.
@MainActor
final class UITestAppleHealthDataReader:
    AppleHealthDataReading,
    AppleHealthReplicaChangeReading
{
    private static let enableArgument = "--uitesting-apple-health"
    private static let historyArgument =
        "--uitesting-apple-health-history"
    private static let failOnceArgument =
        "--uitesting-apple-health-fail-once"
    private static let emptyArgument =
        "--uitesting-apple-health-empty"
    private static let emptyOnceArgument =
        "--uitesting-apple-health-empty-once"
    private static let enableEnvironmentKey =
        "TIMETRACKER_UI_TEST_APPLE_HEALTH"

    private enum FixtureMode {
        case currentDay
        case history
    }

    private let fixtureMode: FixtureMode
    private let returnsEmpty: Bool
    private let referenceDate: Date
    private var shouldInjectReadFailure: Bool
    private var shouldReturnEmptyUntilSceneReactivation: Bool
    private var hasObservedBackgroundTransition = false

    private init(
        arguments: [String],
        referenceDate: Date = Date()
    ) {
        fixtureMode = arguments.contains(Self.historyArgument)
            ? .history
            : .currentDay
        returnsEmpty = arguments.contains(Self.emptyArgument)
        shouldInjectReadFailure = arguments.contains(Self.failOnceArgument)
        shouldReturnEmptyUntilSceneReactivation = arguments.contains(
            Self.emptyOnceArgument
        )
        self.referenceDate = referenceDate
    }

    static func isRequested(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let explicitArguments = [
            enableArgument,
            historyArgument,
            failOnceArgument,
            emptyArgument,
            emptyOnceArgument,
        ]
        return arguments.contains("--uitesting") &&
            (
                explicitArguments.contains { arguments.contains($0) } ||
                    environment[enableEnvironmentKey] == "1"
            )
    }

    static func makeIfRequested(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UITestAppleHealthDataReader? {
        guard isRequested(
            arguments: arguments,
            environment: environment
        ) else {
            return nil
        }
        return UITestAppleHealthDataReader(arguments: arguments)
    }

    static func preferenceStoreIfRequested(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> (any AppleHealthTimelinePreferenceStoring)? {
        guard isRequested(
            arguments: arguments,
            environment: environment
        ) else {
            return nil
        }
        return UITestAppleHealthTimelinePreferenceStore()
    }

    let isHealthDataAvailable = true

    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus
    {
        try Task.checkCancellation()
        return .unnecessary
    }

    func requestReadAuthorization() async throws {
        try Task.checkCancellation()
    }

    func resolveExplicitRetryGate() {
        shouldInjectReadFailure = false
    }

    func resolveSceneReactivationGate() {
        guard hasObservedBackgroundTransition else { return }
        shouldReturnEmptyUntilSceneReactivation = false
    }

    func recordBackgroundTransition() {
        hasObservedBackgroundTransition = true
    }

    func samples(
        overlapping interval: DateInterval
    ) async throws -> AppleHealthSampleBatch {
        try Task.checkCancellation()

        if shouldInjectReadFailure, isTaskDetailHistoryQuery(interval) {
            throw UITestAppleHealthFixtureError.injectedFirstReadFailure
        }
        if shouldReturnEmptyUntilSceneReactivation,
           isTaskDetailHistoryQuery(interval)
        {
            return .empty
        }
        guard returnsEmpty == false, interval.duration > 0 else {
            return .empty
        }

        let batch = switch fixtureMode {
        case .currentDay:
            currentDayBatch(endingAt: interval.end)
        case .history:
            historyBatch()
        }
        return filtered(batch, overlapping: interval)
    }

    func replicaChanges(
        after _: AppleHealthReplicaAnchors
    ) async throws -> AppleHealthReplicaChangeBatch {
        try Task.checkCancellation()

        if shouldInjectReadFailure {
            throw UITestAppleHealthFixtureError.injectedFirstReadFailure
        }
        let batch: AppleHealthSampleBatch = if returnsEmpty || shouldReturnEmptyUntilSceneReactivation {
            .empty
        } else {
            switch fixtureMode {
            case .currentDay:
                currentDayBatch(endingAt: referenceDate)
            case .history:
                historyBatch()
            }
        }
        return AppleHealthReplicaChangeBatch(
            workouts: batch.workouts,
            deletedWorkoutIDs: [],
            workoutAnchor: Data("ui-test-workout-v1".utf8),
            sleep: batch.sleep,
            deletedSleepIDs: [],
            sleepAnchor: Data("ui-test-sleep-v1".utf8)
        )
    }

    private func isTaskDetailHistoryQuery(_ interval: DateInterval) -> Bool {
        guard case .history = fixtureMode else { return false }
        // The Home timeline reads at most Today plus sleep context. Task detail
        // starts on Week and includes its matched comparison period, so this
        // keeps one-shot states owned by the screen under test.
        return interval.duration >= 3 * 24 * 3600
    }

    /// Preserves the original fixture's single-day behavior for existing UI
    /// tests while the explicit history argument opts into the richer batch.
    private func currentDayBatch(endingAt visibleEnd: Date)
        -> AppleHealthSampleBatch
    {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: visibleEnd)
        let availableDuration = visibleEnd.timeIntervalSince(dayStart)
        guard availableDuration > 0 else {
            return .empty
        }

        // Keep both fixture entries inside Today's visible interval at every
        // time of day. At normal review times they retain realistic durations;
        // shortly after midnight they scale down instead of disappearing.
        let sleepDuration = min(
            6.5 * 3600,
            max(availableDuration * 0.65, min(availableDuration, 60))
        )
        let workoutDuration = min(
            45 * 60,
            max(availableDuration * 0.1, min(availableDuration, 60))
        )
        let sleepCoreEnd = dayStart.addingTimeInterval(sleepDuration * 0.40)
        let sleepAwakeEnd = dayStart.addingTimeInterval(sleepDuration * 0.43)
        let sleepDeepEnd = dayStart.addingTimeInterval(sleepDuration * 0.70)
        let sleepEnd = dayStart.addingTimeInterval(sleepDuration)
        let workoutEnd = visibleEnd
        let workoutStart = workoutEnd.addingTimeInterval(-workoutDuration)

        return AppleHealthSampleBatch(
            workouts: [
                AppleHealthWorkoutSample(
                    id: id("D0400000-0000-4000-8000-000000000001"),
                    kind: .running,
                    startedAt: workoutStart,
                    endedAt: workoutEnd,
                    sourceBundleIdentifier: "ui-test.apple-health"
                ),
            ],
            sleep: [
                sleep(
                    id: "D0400000-0000-4000-8000-000000000002",
                    stage: .asleepCore,
                    start: dayStart,
                    end: sleepCoreEnd
                ),
                sleep(
                    id: "D0400000-0000-4000-8000-000000000003",
                    stage: .awake,
                    start: sleepCoreEnd,
                    end: sleepAwakeEnd
                ),
                sleep(
                    id: "D0400000-0000-4000-8000-000000000004",
                    stage: .asleepDeep,
                    start: sleepAwakeEnd,
                    end: sleepDeepEnd
                ),
                sleep(
                    id: "D0400000-0000-4000-8000-000000000005",
                    stage: .asleepREM,
                    start: sleepDeepEnd,
                    end: sleepEnd
                ),
            ]
        )
    }

    /// A relative-date fixture keeps the selected week and month meaningful
    /// without depending on the calendar date of a screenshot run. UUIDs stay
    /// fixed so XCUITest can address an exact imported Health record.
    private func historyBatch() -> AppleHealthSampleBatch {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: referenceDate)
        let availableToday = referenceDate.timeIntervalSince(today)
        let currentDuration = min(
            50 * 60,
            max(availableToday * 0.35, min(availableToday, 60))
        )
        let currentRunning = workout(
            id: "D0410000-0000-4000-8000-000000000001",
            kind: .running,
            start: referenceDate.addingTimeInterval(-currentDuration),
            end: referenceDate
        )

        let workouts = [
            currentRunning,
            workout(
                id: "D0410000-0000-4000-8000-000000000002",
                kind: .walking,
                start: clockDate(
                    dayOffset: -1,
                    hour: 18,
                    minute: 10,
                    calendar: calendar,
                    today: today
                ),
                duration: 42 * 60
            ),
            workout(
                id: "D0410000-0000-4000-8000-000000000003",
                kind: .running,
                start: clockDate(
                    dayOffset: -3,
                    hour: 7,
                    minute: 20,
                    calendar: calendar,
                    today: today
                ),
                duration: 55 * 60
            ),
            workout(
                id: "D0410000-0000-4000-8000-000000000004",
                kind: .walking,
                start: clockDate(
                    dayOffset: -5,
                    hour: 12,
                    minute: 15,
                    calendar: calendar,
                    today: today
                ),
                duration: 35 * 60
            ),
            workout(
                id: "D0410000-0000-4000-8000-000000000005",
                kind: .running,
                start: clockDate(
                    dayOffset: -9,
                    hour: 6,
                    minute: 50,
                    calendar: calendar,
                    today: today
                ),
                duration: 70 * 60
            ),
            workout(
                id: "D0410000-0000-4000-8000-000000000006",
                kind: .walking,
                start: clockDate(
                    dayOffset: -14,
                    hour: 17,
                    minute: 40,
                    calendar: calendar,
                    today: today
                ),
                duration: 48 * 60
            ),
            workout(
                id: "D0410000-0000-4000-8000-000000000007",
                kind: .running,
                start: clockDate(
                    dayOffset: -21,
                    hour: 8,
                    minute: 5,
                    calendar: calendar,
                    today: today
                ),
                duration: 65 * 60
            ),
            workout(
                id: "D0410000-0000-4000-8000-000000000008",
                kind: .walking,
                start: clockDate(
                    dayOffset: -27,
                    hour: 19,
                    minute: 5,
                    calendar: calendar,
                    today: today
                ),
                duration: 30 * 60
            ),
        ]

        let sleepDefinitions: [
            (dayOffset: Int, firstID: Int)
        ] = [
            (-2, 1),
            (-5, 5),
            (-11, 9),
            (-18, 13),
            (-26, 17),
        ]
        let sleepSamples = sleepDefinitions.flatMap { definition in
            sleepEpisode(
                dayOffset: definition.dayOffset,
                firstID: definition.firstID,
                calendar: calendar,
                today: today
            )
        }

        return AppleHealthSampleBatch(
            workouts: workouts,
            sleep: sleepSamples
        )
    }

    private func workout(
        id value: String,
        kind: AppleHealthWorkoutKind,
        start: Date,
        duration: TimeInterval
    ) -> AppleHealthWorkoutSample {
        workout(
            id: value,
            kind: kind,
            start: start,
            end: start.addingTimeInterval(duration)
        )
    }

    private func workout(
        id value: String,
        kind: AppleHealthWorkoutKind,
        start: Date,
        end: Date
    ) -> AppleHealthWorkoutSample {
        AppleHealthWorkoutSample(
            id: id(value),
            kind: kind,
            startedAt: start,
            endedAt: end,
            sourceBundleIdentifier: "ui-test.apple-health"
        )
    }

    private func sleepEpisode(
        dayOffset: Int,
        firstID: Int,
        calendar: Calendar,
        today: Date
    ) -> [AppleHealthSleepSample] {
        let coreStart = clockDate(
            dayOffset: dayOffset,
            hour: 22,
            minute: 15,
            calendar: calendar,
            today: today
        )
        let coreEnd = clockDate(
            dayOffset: dayOffset + 1,
            hour: 0,
            minute: 20,
            calendar: calendar,
            today: today
        )
        let awakeEnd = clockDate(
            dayOffset: dayOffset + 1,
            hour: 0,
            minute: 30,
            calendar: calendar,
            today: today
        )
        let deepEnd = clockDate(
            dayOffset: dayOffset + 1,
            hour: 3,
            minute: 10,
            calendar: calendar,
            today: today
        )
        let remEnd = clockDate(
            dayOffset: dayOffset + 1,
            hour: 6,
            minute: 25,
            calendar: calendar,
            today: today
        )

        return [
            sleep(
                id: historySleepID(firstID),
                stage: .asleepCore,
                start: coreStart,
                end: coreEnd
            ),
            sleep(
                id: historySleepID(firstID + 1),
                stage: .awake,
                start: coreEnd,
                end: awakeEnd
            ),
            sleep(
                id: historySleepID(firstID + 2),
                stage: .asleepDeep,
                start: awakeEnd,
                end: deepEnd
            ),
            sleep(
                id: historySleepID(firstID + 3),
                stage: .asleepREM,
                start: deepEnd,
                end: remEnd
            ),
        ]
    }

    private func historySleepID(_ serial: Int) -> String {
        String(
            format: "D0420000-0000-4000-8000-%012d",
            serial
        )
    }

    private func clockDate(
        dayOffset: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar,
        today: Date
    ) -> Date {
        let day = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: today
        )!
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: day
        )!
    }

    private func filtered(
        _ batch: AppleHealthSampleBatch,
        overlapping interval: DateInterval
    ) -> AppleHealthSampleBatch {
        AppleHealthSampleBatch(
            workouts: batch.workouts.filter { sample in
                overlaps(
                    start: sample.startedAt,
                    end: sample.endedAt,
                    interval: interval
                )
            },
            sleep: batch.sleep.filter { sample in
                overlaps(
                    start: sample.startedAt,
                    end: sample.endedAt,
                    interval: interval
                )
            }
        )
    }

    private func overlaps(
        start: Date,
        end: Date,
        interval: DateInterval
    ) -> Bool {
        start < interval.end && end > interval.start
    }

    private func sleep(
        id value: String,
        stage: AppleHealthSleepStage,
        start: Date,
        end: Date
    ) -> AppleHealthSleepSample {
        AppleHealthSleepSample(
            id: id(value),
            stage: stage,
            startedAt: start,
            endedAt: end,
            sourceBundleIdentifier: "ui-test.apple-health",
            sourceProductType: "WatchUIFixture"
        )
    }

    private func id(_ value: String) -> UUID {
        UUID(uuidString: value)!
    }
}

private enum UITestAppleHealthFixtureError: LocalizedError, Sendable {
    case injectedFirstReadFailure

    var errorDescription: String? {
        "UI test injected an Apple Health read failure."
    }
}

@MainActor
private final class UITestAppleHealthTimelinePreferenceStore:
    AppleHealthTimelinePreferenceStoring
{
    var isTimelineEnabled = false
    var taskCatalogClearRecoveryTaskIDs: Set<UUID> = []
}
#endif
