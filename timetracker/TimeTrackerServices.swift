import Foundation
import SwiftData

struct TimerCommand: Codable, Hashable, Identifiable {
    enum CommandType: String, Codable {
        case startTask
        case stopSegment
        case startPomodoro
    }

    let id: UUID
    let type: CommandType
    let taskID: UUID?
    let segmentID: UUID?
    let issuedAt: Date
    let deviceID: String
}

struct TimeAggregationService {
    func totalSeconds(segments: [TimeSegment], mode: AggregationMode, now: Date = Date()) -> Int {
        switch mode {
        case .gross:
            return grossSeconds(segments, now: now)
        case .wallClock:
            return wallClockSeconds(segments, now: now)
        }
    }

    func grossSeconds(_ segments: [TimeSegment], now: Date = Date()) -> Int {
        segments.reduce(0) { result, segment in
            guard segment.deletedAt == nil else { return result }
            let end = segment.endedAt ?? now
            return result + max(0, Int(end.timeIntervalSince(segment.startedAt)))
        }
    }

    func wallClockSeconds(_ segments: [TimeSegment], now: Date = Date()) -> Int {
        let intervals = segments.compactMap { segment -> DateInterval? in
            guard segment.deletedAt == nil else { return nil }
            let end = segment.endedAt ?? now
            guard end > segment.startedAt else { return nil }
            return DateInterval(start: segment.startedAt, end: end)
        }

        return mergeOverlappingIntervals(intervals).reduce(0) { result, interval in
            result + Int(interval.end.timeIntervalSince(interval.start))
        }
    }

    func mergeOverlappingIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if interval.start <= last.end {
                let end = max(last.end, interval.end)
                merged[merged.count - 1] = DateInterval(start: last.start, end: end)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }
}

enum DurationFormatter {
    static func compact(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func clock(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        let second = safeSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, second)
        }
        return String(format: "%02d:%02d", minutes, second)
    }
}

enum DeviceIdentity {
    static let current: String = {
        let storageKey = "TimeTrackerDeviceID"
        if let existing = UserDefaults.standard.string(forKey: storageKey) {
            return existing
        }

        #if os(macOS)
        let prefix = "mac-\(Host.current().localizedName ?? "local")"
        #elseif os(watchOS)
        let prefix = "watch"
        #else
        let prefix = "ios"
        #endif

        let identifier = "\(prefix)-\(UUID().uuidString)"
        UserDefaults.standard.set(identifier, forKey: storageKey)
        return identifier
    }()
}
