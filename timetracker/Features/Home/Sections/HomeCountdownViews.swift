import SwiftUI

struct HomeCountdownSection: View {
    let store: TimeTrackerStore

    private var events: [CountdownEvent] {
        store.countdownEvents.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: AppStrings.localized("settings.countdown"))

                VStack(spacing: 0) {
                    ForEach(events) { event in
                        HomeCountdownRow(event: event)
                            .padding(14)
                        if event.id != events.last?.id {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .appCard(padding: 0)
            }
            .accessibilityIdentifier("home.countdown")
        }
    }
}

struct HomeCountdownRow: View {
    let event: CountdownEvent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(event.title)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        AppRowIcon(systemImage: "calendar", tint: .purple)
                    }
                    eventDetails
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    AppRowIcon(systemImage: "calendar", tint: .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .lineLimit(2)
                        Text(event.date, format: .dateTime.year().month(.wide).day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(event.date, style: .relative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var eventDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(event.date, format: .dateTime.year().month(.wide).day())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(event.date, style: .relative)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
