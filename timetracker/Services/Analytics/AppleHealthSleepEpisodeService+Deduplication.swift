import Foundation

nonisolated extension AppleHealthSleepEpisodeService {
    func deduplicated(
        _ episodes: [AppleHealthSleepEpisode]
    ) -> [AppleHealthSleepEpisode] {
        var accepted: [AppleHealthSleepEpisode] = []
        for candidate in episodes.sorted(by: preferredEpisodePrecedes) {
            let isDuplicate = accepted.contains {
                $0.source != candidate.source
                    && representsSameSleep($0, candidate)
            }
            if isDuplicate == false {
                accepted.append(candidate)
            }
        }
        return accepted
    }

    func item(
        for episode: AppleHealthSleepEpisode,
        visibleInterval: DateInterval
    ) -> AppleHealthTimelineItem? {
        guard let interval = episode.interval.intersection(with: visibleInterval)
        else {
            return nil
        }
        let durationIntervals = mergedIntervals(
            episode.asleepIntervals.compactMap {
                $0.intersection(with: visibleInterval)
            }
        )
        guard durationIntervals.isEmpty == false else { return nil }
        return AppleHealthTimelineItem(
            id: .appleHealthSleep(episode.anchorSampleID),
            subject: .appleHealthSleep,
            interval: interval,
            durationIntervals: durationIntervals
        )
    }

    func itemPrecedes(
        _ lhs: AppleHealthTimelineItem,
        _ rhs: AppleHealthTimelineItem
    ) -> Bool {
        if lhs.interval.start != rhs.interval.start {
            return lhs.interval.start < rhs.interval.start
        }
        return lhs.id.stableSortKey < rhs.id.stableSortKey
    }

    private func intersectionOverUnion(
        _ lhs: DateInterval,
        _ rhs: DateInterval
    ) -> Double {
        guard let intersection = lhs.intersection(with: rhs) else { return 0 }
        let union = lhs.duration + rhs.duration - intersection.duration
        return union > 0 ? intersection.duration / union : 0
    }

    private func preferredEpisodePrecedes(
        _ lhs: AppleHealthSleepEpisode,
        _ rhs: AppleHealthSleepEpisode
    ) -> Bool {
        if lhs.hasDetailedStages != rhs.hasDetailedStages {
            return lhs.hasDetailedStages
        }
        if lhs.detailedDuration != rhs.detailedDuration {
            return lhs.detailedDuration > rhs.detailedDuration
        }
        if lhs.asleepDuration != rhs.asleepDuration {
            return lhs.asleepDuration > rhs.asleepDuration
        }
        if lhs.interval.start != rhs.interval.start {
            return lhs.interval.start < rhs.interval.start
        }
        if lhs.source != rhs.source {
            return lhs.source < rhs.source
        }
        return lhs.anchorSampleID.uuidString < rhs.anchorSampleID.uuidString
    }

    private func representsSameSleep(
        _ lhs: AppleHealthSleepEpisode,
        _ rhs: AppleHealthSleepEpisode
    ) -> Bool {
        guard intersectionOverUnion(lhs.interval, rhs.interval)
            >= AppleHealthSleepEpisodePolicy.duplicateIntersectionOverUnion
        else {
            return false
        }
        let asleepOverlap = overlapDuration(
            lhs.asleepIntervals,
            rhs.asleepIntervals
        )
        guard lhs.asleepDuration > 0, rhs.asleepDuration > 0 else {
            return false
        }
        return asleepOverlap / lhs.asleepDuration
            >= AppleHealthSleepEpisodePolicy.duplicateMinimumAsleepCoverage
            && asleepOverlap / rhs.asleepDuration
            >= AppleHealthSleepEpisodePolicy
            .duplicateMinimumAsleepCoverage
    }

    private func overlapDuration(
        _ lhs: [DateInterval],
        _ rhs: [DateInterval]
    ) -> TimeInterval {
        var lhsIndex = 0
        var rhsIndex = 0
        var result: TimeInterval = 0
        while lhsIndex < lhs.count, rhsIndex < rhs.count {
            let left = lhs[lhsIndex]
            let right = rhs[rhsIndex]
            if let overlap = left.intersection(with: right) {
                result += overlap.duration
            }
            if left.end <= right.end {
                lhsIndex += 1
            } else {
                rhsIndex += 1
            }
        }
        return result
    }
}
