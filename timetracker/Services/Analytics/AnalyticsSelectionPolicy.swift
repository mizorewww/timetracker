import Foundation

struct AnalyticsPeakHour {
    let hour: Int
    let seconds: Int
}

enum AnalyticsSelectionPolicy {
    static func rankedTasks(_ points: [TaskAnalyticsPoint]) -> [TaskAnalyticsPoint] {
        points.sorted { lhs, rhs in
            if lhs.grossSeconds != rhs.grossSeconds {
                return lhs.grossSeconds > rhs.grossSeconds
            }
            if lhs.wallSeconds != rhs.wallSeconds {
                return lhs.wallSeconds > rhs.wallSeconds
            }
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return lhs.taskID.uuidString < rhs.taskID.uuidString
        }
    }

    /// Selects the earliest local hour when multiple buckets share the peak.
    static func peakHour(in hourlySeconds: [Int: Int]) -> AnalyticsPeakHour? {
        hourlySeconds.reduce(nil) { best, candidate in
            let next = AnalyticsPeakHour(hour: candidate.key, seconds: candidate.value)
            guard let best else { return next }
            if next.seconds != best.seconds {
                return next.seconds > best.seconds ? next : best
            }
            return next.hour < best.hour ? next : best
        }
    }

    static func latestSessionTitleByTaskID(
        sessions: [TimeSession],
        restrictingTo taskIDs: Set<UUID>? = nil
    ) -> [UUID: String] {
        let latestSessionByTaskID = sessions.deduplicatedByID().reduce(
            into: [UUID: TimeSession]()
        ) { result, session in
            guard session.deletedAt == nil,
                  session.titleSnapshot?.isEmpty == false,
                  taskIDs?.contains(session.taskID) != false else {
                return
            }
            guard let existing = result[session.taskID] else {
                result[session.taskID] = session
                return
            }
            if sessionPrecedes(existing, session) {
                result[session.taskID] = session
            }
        }
        return latestSessionByTaskID.compactMapValues(\.titleSnapshot)
    }

    private static func sessionPrecedes(_ lhs: TimeSession, _ rhs: TimeSession) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
