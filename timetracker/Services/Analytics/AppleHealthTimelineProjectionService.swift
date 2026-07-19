import Foundation

nonisolated struct AppleHealthTimelineProjectionService {
    func project(
        batch: AppleHealthSampleBatch,
        visibleInterval: DateInterval
    ) -> [AppleHealthTimelineItem] {
        guard visibleInterval.duration > 0 else { return [] }

        let workouts = canonicalWorkouts(batch.workouts).compactMap { sample -> AppleHealthTimelineItem? in
            guard let interval = clippedInterval(
                startedAt: sample.startedAt,
                endedAt: sample.endedAt,
                to: visibleInterval
            ) else {
                return nil
            }
            return AppleHealthTimelineItem(
                id: .appleHealthWorkout(sample.id),
                subject: .appleHealthWorkout(sample.kind),
                interval: interval
            )
        }
        let sleep = mergedAsleepBlocks(
            asleepFragments(batch.sleep, visibleInterval: visibleInterval)
        )
        return (workouts + sleep).sorted(by: itemPrecedes)
    }

    func clippedInterval(
        startedAt: Date,
        endedAt: Date,
        to visibleInterval: DateInterval
    ) -> DateInterval? {
        guard endedAt > visibleInterval.start,
              startedAt < visibleInterval.end else {
            return nil
        }
        let start = max(startedAt, visibleInterval.start)
        let end = min(endedAt, visibleInterval.end)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    func canonicalWorkouts(
        _ samples: [AppleHealthWorkoutSample]
    ) -> [AppleHealthWorkoutSample] {
        Dictionary(grouping: samples, by: \.id)
            .values
            .compactMap { $0.min(by: workoutCanonicalPrecedes) }
            .sorted(by: AppleHealthSampleBatch.workoutChronology)
    }

    func canonicalSleep(
        _ samples: [AppleHealthSleepSample]
    ) -> [AppleHealthSleepSample] {
        Dictionary(grouping: samples, by: \.id)
            .values
            .compactMap { $0.min(by: sleepCanonicalPrecedes) }
            .sorted(by: AppleHealthSampleBatch.sleepChronology)
    }

    private func asleepFragments(
        _ samples: [AppleHealthSleepSample],
        visibleInterval: DateInterval
    ) -> [AsleepFragment] {
        canonicalSleep(samples).compactMap { sample in
            guard sample.stage.isAsleep,
                  let interval = clippedInterval(
                      startedAt: sample.startedAt,
                      endedAt: sample.endedAt,
                      to: visibleInterval
                  ) else {
                return nil
            }
            return AsleepFragment(sampleID: sample.id, interval: interval)
        }
        .sorted(by: fragmentPrecedes)
    }

    private func mergedAsleepBlocks(
        _ fragments: [AsleepFragment]
    ) -> [AppleHealthTimelineItem] {
        guard var current = fragments.first else { return [] }
        var currentIDs: Set<UUID> = [current.sampleID]
        var result: [AppleHealthTimelineItem] = []

        for fragment in fragments.dropFirst() {
            if fragment.interval.start <= current.interval.end {
                current = AsleepFragment(
                    sampleID: current.sampleID,
                    interval: DateInterval(
                        start: current.interval.start,
                        end: max(current.interval.end, fragment.interval.end)
                    )
                )
                currentIDs.insert(fragment.sampleID)
            } else {
                result.append(sleepItem(interval: current.interval, sampleIDs: currentIDs))
                current = fragment
                currentIDs = [fragment.sampleID]
            }
        }
        result.append(sleepItem(interval: current.interval, sampleIDs: currentIDs))
        return result
    }

    private func sleepItem(
        interval: DateInterval,
        sampleIDs: Set<UUID>
    ) -> AppleHealthTimelineItem {
        let contributingIDs = sampleIDs.sorted {
            $0.uuidString < $1.uuidString
        }
        return AppleHealthTimelineItem(
            id: .appleHealthSleep(contributingIDs),
            subject: .appleHealthSleep,
            interval: interval
        )
    }

    private func workoutCanonicalPrecedes(
        _ lhs: AppleHealthWorkoutSample,
        _ rhs: AppleHealthWorkoutSample
    ) -> Bool {
        let lhsIsValid = lhs.endedAt > lhs.startedAt
        let rhsIsValid = rhs.endedAt > rhs.startedAt
        if lhsIsValid != rhsIsValid { return lhsIsValid }
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        if lhs.endedAt != rhs.endedAt { return lhs.endedAt < rhs.endedAt }
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.sourceBundleIdentifier < rhs.sourceBundleIdentifier
    }

    private func sleepCanonicalPrecedes(
        _ lhs: AppleHealthSleepSample,
        _ rhs: AppleHealthSleepSample
    ) -> Bool {
        let lhsIsValid = lhs.endedAt > lhs.startedAt
        let rhsIsValid = rhs.endedAt > rhs.startedAt
        if lhsIsValid != rhsIsValid { return lhsIsValid }
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        if lhs.endedAt != rhs.endedAt { return lhs.endedAt < rhs.endedAt }
        if lhs.stage.rawValue != rhs.stage.rawValue {
            return lhs.stage.rawValue < rhs.stage.rawValue
        }
        return lhs.sourceBundleIdentifier < rhs.sourceBundleIdentifier
    }

    private func fragmentPrecedes(_ lhs: AsleepFragment, _ rhs: AsleepFragment) -> Bool {
        if lhs.interval.start != rhs.interval.start {
            return lhs.interval.start < rhs.interval.start
        }
        if lhs.interval.end != rhs.interval.end {
            return lhs.interval.end < rhs.interval.end
        }
        return lhs.sampleID.uuidString < rhs.sampleID.uuidString
    }

    private func itemPrecedes(
        _ lhs: AppleHealthTimelineItem,
        _ rhs: AppleHealthTimelineItem
    ) -> Bool {
        if lhs.interval.start != rhs.interval.start {
            return lhs.interval.start < rhs.interval.start
        }
        if lhs.interval.end != rhs.interval.end {
            return lhs.interval.end < rhs.interval.end
        }
        return lhs.id.stableSortKey < rhs.id.stableSortKey
    }
}

private nonisolated struct AsleepFragment {
    let sampleID: UUID
    let interval: DateInterval
}
