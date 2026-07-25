import Foundation

nonisolated enum AppleHealthSleepEpisodePolicy {
    static let unlabeledGapLimit: TimeInterval = 2 * 60
    static let inBedGapLimit: TimeInterval = 10 * 60
    static let awakeGapLimit: TimeInterval = 30 * 60
    static let maximumEpisodeDuration: TimeInterval = 18 * 60 * 60
    static let duplicateIntersectionOverUnion = 0.5
    static let duplicateMinimumAsleepCoverage = 0.8
    static let evidenceCoverageTolerance: TimeInterval = 1
    static let queryContextDuration = maximumEpisodeDuration
}

nonisolated struct AppleHealthSleepEpisodeService {
    func project(
        samples: [AppleHealthSleepSample],
        visibleInterval: DateInterval
    ) -> [AppleHealthTimelineItem] {
        let valid = samples.filter {
            guard $0.endedAt > $0.startedAt else { return false }
            return $0.stage.isAsleep == false
                || $0.endedAt.timeIntervalSince($0.startedAt)
                <= AppleHealthSleepEpisodePolicy.maximumEpisodeDuration
        }
        let bySource = Dictionary(
            grouping: valid,
            by: \.sourceIdentityKey
        )
        let candidates = bySource.keys.sorted().flatMap {
            episodes(for: bySource[$0] ?? [], source: $0)
        }
        return deduplicated(candidates)
            .compactMap { item(for: $0, visibleInterval: visibleInterval) }
            .sorted(by: itemPrecedes)
    }

    private func episodes(
        for samples: [AppleHealthSleepSample],
        source: String
    ) -> [AppleHealthSleepEpisode] {
        let asleep = samples.filter(\.stage.isAsleep).sorted(by: samplePrecedes)
        let awake = evidenceIntervals(in: samples, stage: .awake)
        let inBed = evidenceIntervals(in: samples, stage: .inBed)
        guard let first = asleep.first else { return [] }

        var current = AppleHealthSleepEpisode(sample: first, source: source)
        var result: [AppleHealthSleepEpisode] = []
        for sample in asleep.dropFirst() {
            if shouldMerge(sample, into: current, awake: awake, inBed: inBed) {
                current.append(sample)
            } else {
                result.append(current)
                current = AppleHealthSleepEpisode(sample: sample, source: source)
            }
        }
        result.append(current)
        return result
    }

    private func shouldMerge(
        _ sample: AppleHealthSleepSample,
        into episode: AppleHealthSleepEpisode,
        awake: [DateInterval],
        inBed: [DateInterval]
    ) -> Bool {
        let candidateEnd = max(episode.interval.end, sample.endedAt)
        guard candidateEnd.timeIntervalSince(episode.interval.start)
            <= AppleHealthSleepEpisodePolicy.maximumEpisodeDuration
        else {
            return false
        }
        guard sample.startedAt > episode.interval.end else { return true }

        let gap = DateInterval(
            start: episode.interval.end,
            end: sample.startedAt
        )
        if gap.duration <= AppleHealthSleepEpisodePolicy.unlabeledGapLimit {
            return true
        }
        if gap.duration <= AppleHealthSleepEpisodePolicy.awakeGapLimit,
           isCovered(gap, by: awake)
        {
            return true
        }
        return gap.duration <= AppleHealthSleepEpisodePolicy.inBedGapLimit
            && isCovered(gap, by: inBed)
    }

    private func evidenceIntervals(
        in samples: [AppleHealthSleepSample],
        stage: AppleHealthSleepStage
    ) -> [DateInterval] {
        mergedIntervals(
            samples.compactMap {
                guard $0.stage == stage else { return nil }
                return DateInterval(start: $0.startedAt, end: $0.endedAt)
            }
        )
    }

    private func isCovered(
        _ target: DateInterval,
        by evidence: [DateInterval]
    ) -> Bool {
        var cursor = target.start
        for interval in evidence where interval.end > cursor {
            guard interval.start.timeIntervalSince(cursor)
                <= AppleHealthSleepEpisodePolicy.evidenceCoverageTolerance
            else {
                return false
            }
            cursor = max(cursor, interval.end)
            if cursor.addingTimeInterval(
                AppleHealthSleepEpisodePolicy.evidenceCoverageTolerance
            ) >= target.end {
                return true
            }
        }
        return false
    }

    func mergedIntervals(
        _ intervals: [DateInterval]
    ) -> [DateInterval] {
        let sorted = intervals.filter { $0.duration > 0 }.sorted(by: intervalPrecedes)
        guard var current = sorted.first else { return [] }
        var result: [DateInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(
                    start: current.start,
                    end: max(current.end, interval.end)
                )
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }

    private func samplePrecedes(
        _ lhs: AppleHealthSleepSample,
        _ rhs: AppleHealthSleepSample
    ) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        if lhs.endedAt != rhs.endedAt {
            return lhs.endedAt < rhs.endedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func intervalPrecedes(
        _ lhs: DateInterval,
        _ rhs: DateInterval
    ) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        return lhs.end < rhs.end
    }
}
