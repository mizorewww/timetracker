import SwiftUI
#if os(iOS)
import UIKit
#endif

struct DesktopMainView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 720
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 22) {
                    HeaderBar(store: store, compact: compact)
                    MetricsAndActions(store: store, horizontal: !compact)
                    TimeProgressSection(store: store)
                    TaskForecastSummarySection(store: store)
                    ActiveTimersSection(store: store)
                    PausedSessionsSection(store: store)
                    if !compact {
                        QuickStartSection(store: store)
                    }
                    TimelineSection(store: store)
                }
                .padding(compact ? 18 : 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AppColors.background)
            #if os(iOS)
            .scrollBounceBehavior(.basedOnSize)
            #endif
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.presentNewTask()
                } label: {
                    Label(AppStrings.newTask, systemImage: "plus")
                }

                Button {
                    store.presentManualTime()
                } label: {
                    Label(AppStrings.addTime, systemImage: "calendar.badge.plus")
                }

                Button {
                    store.refreshQuietly()
                } label: {
                    Label(AppStrings.refresh, systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

struct PhoneHomeView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MetricsAndActions(store: store, horizontal: false)
                TimeProgressSection(store: store)
                TaskForecastSummarySection(store: store)
                ActiveTimersSection(store: store)
                PausedSessionsSection(store: store)
                QuickStartSection(store: store)
                TimelineSection(store: store)
                InspectorSummaryCard(store: store)
            }
            .padding(.horizontal, 18)
            .padding(.top, 0)
            .padding(.bottom, 24)
        }
        .background(AppColors.background)
        .navigationTitle(AppStrings.today)
        #if os(iOS)
        .scrollBounceBehavior(.basedOnSize)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: phoneToolbarPlacement) {
                Button {
                    store.presentNewTask()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

struct HeaderBar: View {
    @ObservedObject var store: TimeTrackerStore
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppStrings.today)
                .font(compact ? .largeTitle.bold() : .largeTitle.bold())
            Text(.app("home.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

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

struct TaskForecastSummarySection: View {
    @ObservedObject var store: TimeTrackerStore

    private var forecasts: [TaskForecastItem] {
        let candidates = store.tasks.compactMap { task -> TaskForecastItem? in
            guard task.deletedAt == nil,
                  task.status != .archived,
                  task.status != .completed,
                  let rollup = store.rollup(for: task.id),
                  rollup.isDisplayableForecast else {
                return nil
            }
            return TaskForecastItem(task: task, rollup: rollup)
        }
        .sorted {
            ($0.rollup.remainingSeconds ?? 0) > ($1.rollup.remainingSeconds ?? 0)
        }

        guard let selectedTask = store.selectedTask,
              let selectedRollup = store.rollup(for: selectedTask.id),
              selectedRollup.isDisplayableForecast,
              selectedTask.status != .archived,
              selectedTask.status != .completed else {
            return Array(candidates.prefix(3))
        }

        let withoutSelected = candidates.filter { $0.task.id != selectedTask.id }
        return Array(([TaskForecastItem(task: selectedTask, rollup: selectedRollup)] + withoutSelected).prefix(3))
    }

    var body: some View {
        if !forecasts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: AppStrings.localized("forecast.today.title"))
                ForecastExplanationCallout()

                VStack(spacing: 0) {
                    ForEach(forecasts) { item in
                        ForecastSummaryRow(store: store, task: item.task, rollup: item.rollup)
                        if item.task.id != forecasts.last?.task.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .appCard(padding: 0)
            }
            .accessibilityIdentifier("home.forecasts")
        }
    }
}

private struct TaskForecastItem: Identifiable {
    let task: TaskNode
    let rollup: TaskRollup

    var id: UUID { task.id }
}

private struct ForecastSummaryRow: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    let rollup: TaskRollup

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TaskIcon(task: task, size: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if rollup.checklistProgress.totalCount > 0 {
                        Text(rollup.checklistProgress.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
                Text(store.path(for: task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: rollup.completionFraction)
                    .tint(Color(hex: task.colorHex) ?? .blue)
                Text(rollup.reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let paceText = rollup.historicalPaceDisplayText {
                    Text(paceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                Text(remainingText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                Text(daysText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(task.id)
        }
        .padding(14)
    }

    private var remainingText: String {
        rollup.remainingDisplayText
    }

    private var daysText: String {
        rollup.projectedDays == nil ? rollup.confidence.displayName : rollup.projectedDaysDisplayText
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

private var phoneToolbarPlacement: ToolbarItemPlacement {
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

struct PausedSessionRow: View {
    @ObservedObject var store: TimeTrackerStore
    let session: TimeSession

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.orange)
                .frame(width: 10, height: 10)

            TaskIcon(task: store.task(for: session.taskID))

            VStack(alignment: .leading, spacing: 3) {
                Text(store.task(for: session.taskID)?.title ?? AppStrings.localized("task.deleted"))
                    .font(.headline)
                Text(AppStrings.paused)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.resume(session: session)
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .tint(.blue)

            Button(role: .destructive) {
                store.stop(session: session)
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(session.taskID, revealInToday: false)
        }
        .padding(14)
    }
}

struct ActiveTimerRow: View {
    @ObservedObject var store: TimeTrackerStore
    let segment: TimeSegment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactPhone: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isCompactPhone {
                compactContent
            } else {
                ViewThatFits(in: .horizontal) {
                    regularContent
                    compactContent
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(segment.taskID, revealInToday: false)
        }
        .padding(isCompactPhone ? 10 : 14)
    }

    private var regularContent: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                .frame(width: 10, height: 10)

            TaskIcon(task: store.task(for: segment.taskID))

            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayTitle(for: segment))
                    .font(.headline)
                    .lineLimit(1)
                Text(displayPathText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .frame(minWidth: 86, alignment: .trailing)

            pauseButton(size: 32)
            stopButton(size: 32)
        }
    }

    private var compactContent: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                TaskIcon(task: store.task(for: segment.taskID), size: 34)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(store.displayTitle(for: segment))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(displayPathText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            HStack(spacing: 10) {
                DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)

                pauseButton(size: 30)
                stopButton(size: 30)
            }
        }
    }

    private var displayPathText: String {
        let path = store.displayPath(for: segment)
        return path.isEmpty ? AppStrings.rootTask : path
    }

    private func pauseButton(size: CGFloat) -> some View {
        Button {
            store.pause(segment: segment)
        } label: {
            Image(systemName: "pause.fill")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .tint(.blue)
    }

    private func stopButton(size: CGFloat) -> some View {
        Button(role: .destructive) {
            store.stop(segment: segment)
        } label: {
            Image(systemName: "stop.fill")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
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

struct TimelineRow: View {
    @ObservedObject var store: TimeTrackerStore
    let segment: TimeSegment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactPhone: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var tag: String {
        switch segment.source {
        case .pomodoro: return AppStrings.pomodoro
        case .manual: return AppStrings.localized("source.manual")
        default: return AppStrings.localized("source.timer")
        }
    }

    var body: some View {
        Group {
            if isCompactPhone {
                compactContent
            } else {
                ViewThatFits(in: .horizontal) {
                    regularContent
                    compactContent
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(segment.taskID, revealInToday: false)
        }
        .contextMenu {
            Button {
                store.presentEditSegment(segment)
            } label: {
                Label(AppStrings.localized("timeline.editSegment"), systemImage: "pencil")
            }

            Button {
                store.presentManualTime(taskID: segment.taskID)
            } label: {
                Label(AppStrings.localized("timeline.addSimilarTime"), systemImage: "calendar.badge.plus")
            }

            Divider()

            Button(role: .destructive) {
                store.deleteSegment(segment.id)
            } label: {
                Label(AppStrings.localized("timeline.deleteSegment"), systemImage: "trash")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompactPhone ? 11 : 10)
    }

    private var regularContent: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                .frame(width: 9, height: 9)

            Text(timeRangeText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: isCompactPhone ? 82 : 120, alignment: .leading)

            Text(store.displayTitle(for: segment))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            tagBadge
                .frame(width: 96, alignment: .center)

            durationText
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                    .frame(width: 8, height: 8)
                Text(timeRangeText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                durationText
            }

            HStack(alignment: .center, spacing: 10) {
                Text(store.displayTitle(for: segment))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                tagBadge
            }
        }
    }

    private var tagBadge: some View {
        Text(tag)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tagColor)
            .background(tagColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .lineLimit(1)
    }

    private var durationText: some View {
        Group {
            if segment.endedAt == nil {
                Text(.app("common.now"))
                    .foregroundStyle(.blue)
            } else {
                Text(DurationFormatter.compact(Int((segment.endedAt ?? Date()).timeIntervalSince(segment.startedAt))))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }

    private var tagColor: Color {
        switch segment.source {
        case .pomodoro: return .blue
        case .manual: return .orange
        default: return .secondary
        }
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: segment.startedAt)
        let end = segment.endedAt.map { formatter.string(from: $0) } ?? AppStrings.localized("common.now")
        return "\(start) - \(end)"
    }
}

struct QuickStartSection: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var isEditorPresented = false

    private var selectedIDs: [UUID] {
        store.preferences.quickStartTaskIDs
    }

    private var pinnedTasks: [TaskNode] {
        selectedIDs.compactMap { store.task(for: $0) }
            .filter { $0.deletedAt == nil && $0.status != .archived }
    }

    private var recentFillTasks: [TaskNode] {
        store.frequentRecentTasks(
            excluding: Set(pinnedTasks.map(\.id)),
            limit: 3
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.quickStart)
                        .font(.headline)
                    Text(AppStrings.localized("quickStart.defaultHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isEditorPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .help(AppStrings.localized("quickStart.edit"))
            }

            if pinnedTasks.isEmpty && recentFillTasks.isEmpty {
                ContentUnavailableView(
                    AppStrings.localized("quickStart.empty.title"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(.app("quickStart.empty.description"))
                )
                .frame(maxWidth: .infinity, minHeight: 104)
            } else {
                if !pinnedTasks.isEmpty {
                    QuickStartTaskGroup(
                        title: AppStrings.localized("quickStart.pinnedTasks"),
                        tasks: pinnedTasks,
                        store: store
                    )
                }

                if !recentFillTasks.isEmpty {
                    QuickStartTaskGroup(
                        title: AppStrings.localized("quickStart.recentTasks"),
                        tasks: recentFillTasks,
                        store: store
                    )
                }
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            QuickStartEditorSheet(
                store: store,
                selectedIDs: selectedIDs,
                onSave: { ids in
                    store.setQuickStartTaskIDs(ids)
                }
            )
        }
    }
}

private struct QuickStartTaskGroup: View {
    let title: String
    let tasks: [TaskNode]
    @ObservedObject var store: TimeTrackerStore

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tasks, id: \.id) { task in
                    QuickStartTaskButton(task: task) {
                        store.startTask(task)
                    }
                }
            }
        }
    }
}

private struct QuickStartTaskButton: View {
    let task: TaskNode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: task.iconName ?? "play")
                    .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
                    .frame(width: 18)
                Text(task.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color(hex: task.colorHex) ?? .blue)
    }
}

struct QuickStartEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: [UUID]
    let onSave: ([UUID]) -> Void

    init(store: TimeTrackerStore, selectedIDs: [UUID], onSave: @escaping ([UUID]) -> Void) {
        self.store = store
        self.onSave = onSave
        _selectedIDs = State(initialValue: selectedIDs)
    }

    private var availableTasks: [TaskNode] {
        store.tasks.filter { $0.deletedAt == nil && $0.status != .archived }
    }

    private var pinnedTasks: [TaskNode] {
        selectedIDs.compactMap { store.task(for: $0) }
            .filter { $0.deletedAt == nil && $0.status != .archived }
    }

    private func isPinned(_ task: TaskNode) -> Bool {
        selectedIDs.contains(task.id)
    }

    private func togglePinned(_ task: TaskNode) {
        if let index = selectedIDs.firstIndex(of: task.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(task.id)
        }
    }

    private func cleanedPinnedIDs() -> [UUID] {
        selectedIDs.filter { id in
            guard let task = store.task(for: id) else { return false }
            return task.deletedAt == nil && task.status != .archived
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if pinnedTasks.isEmpty {
                        Label(AppStrings.localized("quickStart.auto"), systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(pinnedTasks.enumerated()), id: \.element.id) { index, task in
                            QuickStartPinnedTaskRow(task: task, path: store.path(for: task), order: index + 1)
                        }
                        .onDelete { offsets in
                            selectedIDs.remove(atOffsets: offsets)
                        }
                    }

                    if !selectedIDs.isEmpty {
                        Button(role: .destructive) {
                            selectedIDs.removeAll()
                        } label: {
                            Label(AppStrings.localized("quickStart.clearPinned"), systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text(String(format: AppStrings.localized("quickStart.pinnedHeader"), pinnedTasks.count))
                } footer: {
                    Text(.app("quickStart.pinnedFooter"))
                }

                Section(AppStrings.localized("quickStart.allTasks")) {
                    ForEach(availableTasks, id: \.id) { task in
                        let pinned = isPinned(task)
                        Button {
                            togglePinned(task)
                        } label: {
                            QuickStartSelectableTaskRow(
                                task: task,
                                path: store.path(for: task),
                                isPinned: pinned,
                                order: selectedIDs.firstIndex(of: task.id).map { $0 + 1 },
                                isDisabled: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle(AppStrings.localized("quickStart.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(cleanedPinnedIDs())
                        dismiss()
                    }
                }
            }
        }
        .platformSheetFrame(width: 420, height: 520)
    }
}

private struct QuickStartPinnedTaskRow: View {
    let task: TaskNode
    let path: String
    let order: Int

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(.primary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("#\(order)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuickStartSelectableTaskRow: View {
    let task: TaskNode
    let path: String
    let isPinned: Bool
    let order: Int?
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let order {
                Text("#\(order)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Image(systemName: isPinned ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(isPinned ? .blue : .secondary)
        }
        .contentShape(Rectangle())
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}
