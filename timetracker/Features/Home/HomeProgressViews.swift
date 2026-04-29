import SwiftUI

struct TimeProgressSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let items = progressItems(now: context.date)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    TimeProgressTile(item: item)
                }
            }
        }
    }

    private func progressItems(now: Date) -> [TimeProgressItem] {
        let calendar = Calendar.current
        let countdownItems = store.countdownEvents.map { event in
            let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: event.date)).day ?? 0)
            return TimeProgressItem(id: event.id.uuidString, title: event.title, value: String(format: AppStrings.localized("common.days"), days), fraction: days == 0 ? 1 : 0, tint: .purple)
        }

        return [
            item(id: "today", AppStrings.localized("progress.today"), interval: calendar.dateInterval(of: .day, for: now), now: now),
            item(id: "week", AppStrings.localized("progress.week"), interval: calendar.dateInterval(of: .weekOfYear, for: now), now: now),
            item(id: "month", AppStrings.localized("progress.month"), interval: calendar.dateInterval(of: .month, for: now), now: now),
            item(id: "year", AppStrings.localized("progress.year"), interval: calendar.dateInterval(of: .year, for: now), now: now)
        ] + countdownItems
    }

    private func item(id: String, _ title: String, interval: DateInterval?, now: Date) -> TimeProgressItem {
        guard let interval else {
            return TimeProgressItem(id: id, title: title, value: "--", fraction: 0, tint: .secondary)
        }
        let fraction = min(1, max(0, now.timeIntervalSince(interval.start) / interval.duration))
        return TimeProgressItem(id: id, title: title, value: "\(Int(fraction * 100))%", fraction: fraction, tint: .blue)
    }
}

struct TimeProgressItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let fraction: Double
    let tint: Color
}

struct TimeProgressTile: View {
    let item: TimeProgressItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            ProgressView(value: item.fraction)
                .tint(item.tint)
        }
        .appCard(padding: 12)
    }
}
