import SwiftUI
#if os(iOS)
import UIKit
#endif

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

struct MetricsAndActions: View {
    @ObservedObject var store: TimeTrackerStore
    let horizontal: Bool

    var body: some View {
        Group {
            if horizontal {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 14) {
                        MetricsPanelContent(store: store)
                            .frame(maxWidth: .infinity)

                        Divider()
                            .frame(height: 64)

                        ActionStack(store: store, buttonHeight: 36, spacing: 8)
                            .frame(width: 190)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)
                    .appCard(padding: 0)

                    VStack(spacing: 16) {
                        MetricsPanel(store: store)
                        ActionStack(store: store, buttonHeight: 40)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    MetricsPanel(store: store)
                    ActionStack(store: store, buttonHeight: 44, spacing: 10)
                }
            }
        }
    }
}

var phoneToolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
    return .topBarTrailing
    #else
    return .automatic
    #endif
}

struct MetricsPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactPhone: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        MetricsPanelContent(store: store)
            .padding(isCompactPhone ? 12 : 14)
            .frame(maxWidth: .infinity)
            .appCard(padding: 0)
    }
}

private struct MetricsPanelContent: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactPhone: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let metrics = metricItems(now: context.date)
            if isCompactPhone {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(metrics) { metric in
                        MetricCell(metric: metric, compact: true)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        ForEach(metrics) { metric in
                            MetricCell(metric: metric, compact: false)
                            if metric.id != metrics.last?.id {
                                Divider()
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(metrics) { metric in
                            MetricCell(metric: metric, compact: false)
                            if metric.id != metrics.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func metricItems(now: Date) -> [MetricSummaryItem] {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let todayGross = store.todayGrossSeconds(now: now)
        let todayWall = store.todayWallSeconds(now: now)
        let yesterdayGross = store.daySeconds(for: yesterday, mode: .gross, now: now)
        let yesterdayWall = store.daySeconds(for: yesterday, mode: .wallClock, now: now)
        let grossTrend = trend(current: todayGross, previous: yesterdayGross)
        let wallTrend = trend(current: todayWall, previous: yesterdayWall)

        return [
            MetricSummaryItem(
                id: "tracked",
                title: AppStrings.todayTracked,
                value: DurationFormatter.compact(todayGross),
                iconName: "clock.badge.checkmark",
                tint: .blue,
                trendText: grossTrend.text,
                trendColor: grossTrend.color,
                alignment: .leading
            ),
            MetricSummaryItem(
                id: "wall",
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(todayWall),
                iconName: "timeline.selection",
                tint: .green,
                trendText: wallTrend.text,
                trendColor: wallTrend.color,
                alignment: .center
            ),
            MetricSummaryItem(
                id: "gross",
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(todayGross),
                iconName: "square.stack.3d.up",
                tint: .orange,
                trendText: grossTrend.text,
                trendColor: grossTrend.color,
                alignment: .trailing
            )
        ]
    }

    private func trend(current: Int, previous: Int) -> (text: String, color: Color) {
        guard previous > 0 else {
            return (AppStrings.localized("home.metric.noComparison"), .secondary)
        }
        let percent = Int(round((Double(current - previous) / Double(previous)) * 100))
        if percent > 0 {
            return (String(format: AppStrings.localized("home.metric.upFromYesterday"), percent), .green)
        }
        if percent < 0 {
            return (String(format: AppStrings.localized("home.metric.downFromYesterday"), abs(percent)), .red)
        }
        return (AppStrings.localized("home.metric.sameAsYesterday"), .secondary)
    }
}

struct MetricSummaryItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let iconName: String
    let tint: Color
    let trendText: String
    let trendColor: Color
    let alignment: MetricTextAlignment
}

enum MetricTextAlignment {
    case leading
    case center
    case trailing

    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

struct MetricCell: View {
    let metric: MetricSummaryItem
    var compact: Bool = false

    var body: some View {
        VStack(alignment: metric.alignment.horizontalAlignment, spacing: compact ? 4 : 6) {
            HStack(spacing: 5) {
                Image(systemName: metric.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(metric.tint)
                Text(metric.title)
                    .font((compact ? Font.caption2 : Font.caption).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)

            Text(metric.value)
                .font(.system(size: compact ? 20 : 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)

            Text(metric.trendText)
                .font(.caption2)
                .foregroundStyle(metric.trendColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)
        }
        .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)
        .padding(.horizontal, compact ? 4 : 10)
    }
}

struct MiniBars: View {
    let values: [Int]
    let tint: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 4, height: CGFloat(max(3, value * 2)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ActionStack: View {
    @ObservedObject var store: TimeTrackerStore
    var buttonHeight: CGFloat?
    var spacing: CGFloat = 12
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isTaskPickerPresented = false

    private var isCompactPhone: Bool {
        horizontalSizeClass == .compact
    }
#endif

    var body: some View {
        actionLayout
#if os(iOS)
        .sheet(isPresented: $isTaskPickerPresented) {
            NavigationStack {
                TaskStartPicker(store: store) {
                    isTaskPickerPresented = false
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Color(uiColor: .systemGroupedBackground))
        }
#endif
    }

    @ViewBuilder
    private var actionLayout: some View {
#if os(iOS)
        if isCompactPhone {
            HStack(spacing: spacing) {
                startButton
                    .frame(maxWidth: .infinity)
                newTaskButton
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: spacing) {
                startButton
                newTaskButton
            }
        }
#else
        VStack(spacing: spacing) {
            startButton
            newTaskButton
        }
#endif
    }

    private var startButton: some View {
        Button {
#if os(iOS)
            if horizontalSizeClass == .compact {
                isTaskPickerPresented = true
            } else {
                store.startSelectedTask()
            }
#else
            store.startSelectedTask()
#endif
        } label: {
            actionLabel(title: AppStrings.startTimer, systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .accessibilityIdentifier("home.startTimer")
    }

    private var newTaskButton: some View {
        Button {
            store.presentNewTask()
        } label: {
            actionLabel(title: AppStrings.newTask, systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityIdentifier("home.newTask")
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .frame(height: buttonHeight)
        .frame(minHeight: buttonHeight == nil ? 44 : 0)
    }
}

#if os(iOS)
struct TaskStartPicker: View {
    @ObservedObject var store: TimeTrackerStore
    let onDone: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(store.tasks.filter { $0.deletedAt == nil && $0.status != .archived }, id: \.id) { task in
                    Button {
                        store.startTask(task)
                        onDone()
                    } label: {
                        HStack(spacing: 12) {
                            TaskIcon(task: task, size: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title)
                                    .foregroundStyle(.primary)
                                Text(store.path(for: task))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if store.activeSegment(for: task.id) != nil {
                                Text(AppStrings.running)
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            } header: {
                Text(.app("timer.chooseTaskHeader"))
            } footer: {
                Text(.app("timer.chooseTaskFooter"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(AppStrings.startTimer)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.cancel, action: onDone)
            }
        }
    }
}
#endif
