import Foundation

struct TaskAnalyticsPoint: Identifiable {
    let taskID: UUID
    let title: String
    let path: String
    let colorHex: String?
    let iconName: String?
    let grossSeconds: Int
    let wallSeconds: Int

    var id: UUID {
        taskID
    }
}

struct AnalyticsGroupBreakdownPoint: Identifiable {
    enum GroupKind: String {
        case rootTask
        case category
    }

    let id: String
    let kind: GroupKind
    let title: String
    let subtitle: String
    let iconName: String
    let colorHex: String
    let grossSeconds: Int
    let wallSeconds: Int
}

struct TaskRecentRecordPoint: Identifiable {
    let id: TimelineEntryID
    let taskID: UUID
    let title: String
    let path: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int

    init(
        id: TimelineEntryID,
        taskID: UUID,
        title: String,
        path: String,
        startedAt: Date,
        endedAt: Date?,
        durationSeconds: Int
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.path = path
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
    }

    init(
        id: UUID,
        taskID: UUID,
        title: String,
        path: String,
        startedAt: Date,
        endedAt: Date?,
        durationSeconds: Int
    ) {
        self.init(
            id: .trackedSegment(id),
            taskID: taskID,
            title: title,
            path: path,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds
        )
    }
}

struct TaskAnalyticsSnapshot {
    enum Source: Equatable, Sendable {
        case tracked
        case appleHealth
    }

    let source: Source
    let taskID: UUID
    let range: AnalyticsRange
    let overview: AnalyticsOverview
    let comparison: AnalyticsComparison
    let rhythm: AnalyticsRhythm
    let quality: AnalyticsQuality
    let directSeconds: Int
    let descendantSeconds: Int
    let childBreakdown: [AnalyticsGroupBreakdownPoint]
    let daily: [DailyAnalyticsPoint]
    let recentRecords: [TaskRecentRecordPoint]

    init(
        source: Source = .tracked,
        taskID: UUID,
        range: AnalyticsRange,
        overview: AnalyticsOverview,
        comparison: AnalyticsComparison,
        rhythm: AnalyticsRhythm,
        quality: AnalyticsQuality,
        directSeconds: Int,
        descendantSeconds: Int,
        childBreakdown: [AnalyticsGroupBreakdownPoint],
        daily: [DailyAnalyticsPoint],
        recentRecords: [TaskRecentRecordPoint]
    ) {
        self.source = source
        self.taskID = taskID
        self.range = range
        self.overview = overview
        self.comparison = comparison
        self.rhythm = rhythm
        self.quality = quality
        self.directSeconds = directSeconds
        self.descendantSeconds = descendantSeconds
        self.childBreakdown = childBreakdown
        self.daily = daily
        self.recentRecords = recentRecords
    }
}

extension TaskRecentRecordPoint {
    func displayDurationSeconds(
        source: TaskAnalyticsSnapshot.Source,
        now: Date
    ) -> Int {
        switch source {
        case .tracked:
            TrackedTimePolicy.elapsedSeconds(
                startedAt: startedAt,
                endedAt: endedAt,
                now: now
            )
        case .appleHealth:
            // A sleep episode's envelope can include awake evidence that keeps
            // adjacent stages in one record. Its measured duration deliberately
            // excludes those awake gaps.
            max(0, durationSeconds)
        }
    }
}
