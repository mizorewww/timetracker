import SwiftUI

struct ActiveTimersSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.activeTimers)

            VStack(spacing: 0) {
                if store.activeSegments.isEmpty {
                    EmptyStateRow(title: AppStrings.noActiveTimers, icon: "pause.circle")
                } else {
                    ForEach(store.activeSegments, id: \.id) { segment in
                        ActiveTimerRow(store: store, segment: segment)
                        if segment.id != store.activeSegments.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .appCard(padding: 0)
        }
        .accessibilityIdentifier("home.activeTimers")
    }
}

struct PausedSessionsSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        Group {
            if !store.pausedSessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: AppStrings.pausedSessions)

                    VStack(spacing: 0) {
                        ForEach(store.pausedSessions, id: \.id) { session in
                            PausedSessionRow(store: store, session: session)
                            if session.id != store.pausedSessions.last?.id {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                    .appCard(padding: 0)
                }
            }
        }
        .accessibilityIdentifier("home.pausedSessions")
    }
}

struct TimelineSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.todayTimeline)

            VStack(spacing: 0) {
                if store.timelineSegments.isEmpty {
                    EmptyStateRow(title: AppStrings.noTodaySegments, icon: "clock")
                } else {
                    ForEach(store.timelineSegments, id: \.id) { segment in
                        TimelineRow(store: store, segment: segment)
                        if segment.id != store.timelineSegments.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .appCard(padding: 0)
        }
        .accessibilityIdentifier("home.timeline")
    }
}
