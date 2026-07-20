import Foundation

nonisolated enum TimelineEntrySubject: Equatable, Sendable {
    case task(UUID)
    case appleHealthWorkout(AppleHealthWorkoutKind)
    case appleHealthSleep

    var taskID: UUID? {
        guard case let .task(id) = self else { return nil }
        return id
    }

    var isAppleHealth: Bool {
        switch self {
        case .task:
            false
        case .appleHealthWorkout, .appleHealthSleep:
            true
        }
    }
}

nonisolated struct TimelinePresentationSeed: Identifiable, Equatable, Sendable {
    let id: TimelineEntryID
    let subject: TimelineEntrySubject
    let title: String
    let path: String
    let iconName: String
    let colorHex: String
    /// Visual placement envelope.
    let interval: DateInterval
    /// Counted intervals, kept separate so clipping does not inflate duration.
    let durationIntervals: [DateInterval]

    init(
        id: TimelineEntryID,
        subject: TimelineEntrySubject,
        title: String,
        path: String,
        iconName: String,
        colorHex: String,
        interval: DateInterval,
        durationIntervals: [DateInterval]? = nil
    ) {
        self.id = id
        self.subject = subject
        self.title = title
        self.path = path
        self.iconName = iconName
        self.colorHex = colorHex
        self.interval = interval
        self.durationIntervals = durationIntervals ?? [interval]
    }
}

nonisolated struct AnalyticsTimelineSnapshot: Equatable, Sendable {
    let entries: [AnalyticsTimelineEntry]
    let displayInterval: DateInterval?
    let axisCompression: TimelineAxisCompression?

    static let empty = AnalyticsTimelineSnapshot(
        entries: [],
        displayInterval: nil,
        axisCompression: nil
    )

    var laneCount: Int {
        (entries.map(\.lane).max() ?? -1) + 1
    }
}

nonisolated struct AnalyticsTimelineEntry: Identifiable, Equatable, Sendable {
    let id: TimelineEntryID
    let subject: TimelineEntrySubject
    let title: String
    let path: String
    let iconName: String
    let colorHex: String
    let startedAt: Date
    let endedAt: Date
    let lane: Int
    let labelIndex: Int
    let interval: DateInterval
    /// Counted duration after visible-range clipping, not necessarily envelope time.
    let durationSeconds: Int

    var taskID: UUID? {
        subject.taskID
    }
}
