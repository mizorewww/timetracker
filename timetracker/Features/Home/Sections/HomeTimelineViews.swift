import SwiftUI

/// Today's timeline chart and the newest-first record rows under it, as a
/// grouped list section (compact) or a titled card (regular canvas).
struct HomeTimelineSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer
    let live: TodayLiveSnapshot
    let openTask: (UUID) -> Void

    var body: some View {
        switch container {
        case .listSection:
            Section {
                if live.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(AppStrings.noTodaySegments, systemImage: "clock")
                            .foregroundStyle(.secondary)
                        Text(.app("empty.noTodaySegments.description"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityElement(children: .combine)
                } else {
                    chart(compactHeight: 340)
                    rows(showsDividers: false)
                }
            } header: {
                Text(AppStrings.todayTimeline)
                    .accessibilityIdentifier("home.timeline")
            }
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: AppStrings.todayTimeline)

                LazyVStack(spacing: 0) {
                    if live.rows.isEmpty {
                        ContentUnavailableView {
                            Label(AppStrings.noTodaySegments, systemImage: "clock")
                        } description: {
                            Text(.app("empty.noTodaySegments.description"))
                        }
                        .padding(18)
                    } else {
                        chart(compactHeight: 320)
                            .padding(16)
                        Divider()
                        rows(showsDividers: true)
                    }
                }
                .appCard(padding: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.timeline")
        }
    }

    private func chart(compactHeight: CGFloat) -> some View {
        TimelineChart(timeline: live.timeline, compactHeight: compactHeight)
            .accessibilityIdentifier("home.timeline.chart")
    }

    private func rows(showsDividers: Bool) -> some View {
        let lastEntryID = live.rows.last?.id
        return ForEach(live.rows) { entry in
            TodayTimelineEntryRow(
                store: store,
                entry: entry,
                segmentByID: live.segmentByID,
                showsDivider: showsDividers && entry.id != lastEntryID,
                openTaskDetail: openTask
            )
        }
    }
}
