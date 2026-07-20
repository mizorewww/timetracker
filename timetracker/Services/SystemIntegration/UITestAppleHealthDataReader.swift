#if DEBUG && os(iOS)
import Foundation

/// Deterministic, in-memory Health samples for UI verification. The factory
/// requires both UI-test arguments so ordinary Debug launches keep using
/// HealthKit, and Release builds contain no fixture path.
@MainActor
final class UITestAppleHealthDataReader: AppleHealthDataReading {
    private static let enableArgument = "--uitesting-apple-health"

    static func isRequested(
        arguments: [String] = CommandLine.arguments
    ) -> Bool {
        arguments.contains("--uitesting") &&
            arguments.contains(enableArgument)
    }

    static func makeIfRequested(
        arguments: [String] = CommandLine.arguments
    ) -> UITestAppleHealthDataReader? {
        guard isRequested(arguments: arguments) else {
            return nil
        }
        return UITestAppleHealthDataReader()
    }

    static func preferenceStoreIfRequested(
        arguments: [String] = CommandLine.arguments
    ) -> (any AppleHealthTimelinePreferenceStoring)? {
        guard isRequested(arguments: arguments) else {
            return nil
        }
        return UITestAppleHealthTimelinePreferenceStore()
    }

    let isHealthDataAvailable = true

    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus {
        try Task.checkCancellation()
        return .unnecessary
    }

    func requestReadAuthorization() async throws {
        try Task.checkCancellation()
    }

    func samples(
        overlapping interval: DateInterval
    ) async throws -> AppleHealthSampleBatch {
        try Task.checkCancellation()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: interval.end)
        let availableDuration = interval.end.timeIntervalSince(dayStart)
        guard availableDuration > 0 else {
            return AppleHealthSampleBatch(workouts: [], sleep: [])
        }

        // Keep both fixture entries inside Today's visible interval at every
        // time of day. At normal review times they retain realistic durations;
        // shortly after midnight they scale down instead of disappearing.
        let sleepDuration = min(
            6.5 * 3_600,
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
        let workoutEnd = interval.end
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

@MainActor
private final class UITestAppleHealthTimelinePreferenceStore:
    AppleHealthTimelinePreferenceStoring {
    var isTimelineEnabled = false
    var taskCatalogClearRecoveryTaskIDs: Set<UUID> = []
}
#endif
