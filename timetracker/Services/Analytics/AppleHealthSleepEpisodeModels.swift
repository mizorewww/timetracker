import Foundation

nonisolated struct AppleHealthSleepEpisode {
    let source: String
    let anchorSampleID: UUID
    private(set) var interval: DateInterval
    private(set) var asleepIntervals: [DateInterval]
    private(set) var detailedIntervals: [DateInterval]

    init(sample: AppleHealthSleepSample, source: String) {
        self.source = source
        anchorSampleID = sample.id
        interval = DateInterval(start: sample.startedAt, end: sample.endedAt)
        asleepIntervals = [interval]
        detailedIntervals = sample.stage.isDetailed ? [interval] : []
    }

    mutating func append(_ sample: AppleHealthSleepSample) {
        interval = DateInterval(
            start: interval.start,
            end: max(interval.end, sample.endedAt)
        )
        let sampleInterval = DateInterval(
            start: sample.startedAt,
            end: sample.endedAt
        )
        Self.appendMerged(sampleInterval, to: &asleepIntervals)
        if sample.stage.isDetailed {
            Self.appendMerged(sampleInterval, to: &detailedIntervals)
        }
    }

    var asleepDuration: TimeInterval {
        asleepIntervals.reduce(0) { $0 + $1.duration }
    }

    var hasDetailedStages: Bool {
        detailedIntervals.isEmpty == false
    }

    var detailedDuration: TimeInterval {
        detailedIntervals.reduce(0) { $0 + $1.duration }
    }

    private static func appendMerged(
        _ interval: DateInterval,
        to intervals: inout [DateInterval]
    ) {
        guard let last = intervals.last,
              interval.start <= last.end else {
            intervals.append(interval)
            return
        }
        intervals[intervals.index(before: intervals.endIndex)] = DateInterval(
            start: last.start,
            end: max(last.end, interval.end)
        )
    }
}

extension AppleHealthSleepStage {
    nonisolated var isDetailed: Bool {
        switch self {
        case .asleepCore, .asleepDeep, .asleepREM:
            true
        case .inBed, .awake, .asleepUnspecified:
            false
        }
    }
}
