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
                    ActiveTimersSection(store: store)
                    PausedSessionsSection(store: store)
                    TimelineSection(store: store)
                    if !compact {
                        QuickStartSection(store: store)
                    }
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
                ActiveTimersSection(store: store)
                PausedSessionsSection(store: store)
                TimelineSection(store: store)
                QuickStartSection(store: store)
                InspectorSummaryCard(store: store)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
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

struct MetricsAndActions: View {
    @ObservedObject var store: TimeTrackerStore
    let horizontal: Bool

    var body: some View {
        Group {
            if horizontal {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        MetricsPanelContent(store: store)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)

                        Divider()
                            .padding(.vertical, 12)

                        ActionStack(store: store, buttonHeight: 42, spacing: 8)
                            .frame(minWidth: 180, idealWidth: 210, maxWidth: 240)
                            .padding(.vertical, 12)
                            .padding(.trailing, 14)
                    }
                    .frame(minHeight: 108)
                    .appCard(padding: 0)

                    VStack(spacing: 16) {
                        MetricsPanel(store: store)
                        ActionStack(store: store)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    MetricsPanel(store: store)
                    ActionStack(store: store)
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
            .padding(isCompactPhone ? 14 : 18)
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
            if isCompactPhone {
                HStack(alignment: .top, spacing: 0) {
                    MetricCell(title: AppStrings.todayTracked, value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .blue, isMuted: false, values: [], showsBars: false, alignment: .leading, compact: true)
                    MetricCell(title: AppStrings.wallTime, value: DurationFormatter.compact(store.todayWallSeconds(now: context.date)), tint: .gray, isMuted: true, values: [], showsBars: false, alignment: .center, compact: true)
                    MetricCell(title: AppStrings.grossTime, value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .gray, isMuted: true, values: [], showsBars: false, alignment: .trailing, compact: true)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        MetricCell(title: AppStrings.todayTracked, value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .blue, isMuted: false, values: [], showsBars: false)
                        Divider()
                        MetricCell(title: AppStrings.wallTime, value: DurationFormatter.compact(store.todayWallSeconds(now: context.date)), tint: .gray, isMuted: true, values: [], showsBars: false)
                        Divider()
                        MetricCell(title: AppStrings.grossTime, value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .gray, isMuted: true, values: [], showsBars: false)
                    }

                    VStack(spacing: 12) {
                        MetricCell(title: AppStrings.todayTracked, value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .blue, isMuted: false, values: [], showsBars: false)
                        Divider()
                        HStack(spacing: 0) {
                            MetricCell(title: AppStrings.wallTime, value: DurationFormatter.compact(store.todayWallSeconds(now: context.date)), tint: .gray, isMuted: true, values: [], showsBars: false)
                            Divider()
                            MetricCell(title: AppStrings.grossTime, value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .gray, isMuted: true, values: [], showsBars: false)
                        }
                    }
                }
            }
        }
    }
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
    let title: String
    let value: String
    let tint: Color
    let isMuted: Bool
    let values: [Int]
    var showsBars: Bool = true
    var alignment: MetricTextAlignment = .center
    var compact: Bool = false

    var body: some View {
        VStack(alignment: showsBars ? .leading : alignment.horizontalAlignment, spacing: compact ? 6 : 8) {
            HStack {
                if !isMuted {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font((compact ? Font.caption : Font.subheadline).weight(.medium))
                    .foregroundStyle(isMuted ? .primary : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: showsBars ? .leading : alignment.frameAlignment)

            Text(value)
                .font(.system(size: compact ? 24 : 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: showsBars ? .leading : alignment.frameAlignment)

            if showsBars {
                MiniBars(values: values, tint: isMuted ? .gray.opacity(0.38) : tint)
                    .frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: showsBars ? .leading : alignment.frameAlignment)
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
#endif

    var body: some View {
        VStack(spacing: spacing) {
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
                Label(AppStrings.startTimer, systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .frame(minHeight: buttonHeight == nil ? 52 : 0)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("home.startTimer")

            Button {
                store.presentNewTask()
            } label: {
                Label(AppStrings.newTask, systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .frame(minHeight: buttonHeight == nil ? 52 : 0)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("home.newTask")
        }
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
    @AppStorage("QuickStartTaskIDs") private var quickStartTaskIDs = ""
    @State private var isEditorPresented = false

    private var selectedIDs: [UUID] {
        quickStartTaskIDs
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }

    private var quickStartTasks: [TaskNode] {
        let ids = selectedIDs
        guard !ids.isEmpty else { return store.recentTasks }
        return ids.compactMap { store.task(for: $0) }.filter { $0.deletedAt == nil && $0.status != .archived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.quickStart)
                        .font(.headline)
                    Text(selectedIDs.isEmpty ? AppStrings.localized("quickStart.defaultHint") : AppStrings.localized("quickStart.pinnedHint"))
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(quickStartTasks, id: \.id) { task in
                    Button {
                        store.startTask(task)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: task.iconName ?? "play")
                                .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
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

                Button {
                    store.presentNewTask()
                } label: {
                    Label(AppStrings.newTask, systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            QuickStartEditorSheet(
                store: store,
                selectedIDs: selectedIDs,
                onSave: { ids in
                    quickStartTaskIDs = ids.map(\.uuidString).joined(separator: ",")
                }
            )
        }
    }
}

struct QuickStartEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs: Set<UUID>
    let onSave: ([UUID]) -> Void

    init(store: TimeTrackerStore, selectedIDs: [UUID], onSave: @escaping ([UUID]) -> Void) {
        self.store = store
        self.onSave = onSave
        _selectedIDs = State(initialValue: Set(selectedIDs))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedIDs.removeAll()
                    } label: {
                        Label(AppStrings.localized("quickStart.auto"), systemImage: "clock.arrow.circlepath")
                    }
                } footer: {
                    Text(.app("quickStart.auto.footer"))
                }

                Section(AppStrings.localized("quickStart.pinnedTasks")) {
                    ForEach(store.tasks.filter { $0.deletedAt == nil && $0.status != .archived }, id: \.id) { task in
                        Button {
                            if selectedIDs.contains(task.id) {
                                selectedIDs.remove(task.id)
                            } else {
                                selectedIDs.insert(task.id)
                            }
                        } label: {
                            HStack {
                                TaskIcon(task: task, size: 24)
                                VStack(alignment: .leading) {
                                    Text(task.title)
                                    Text(store.path(for: task))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedIDs.contains(task.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(AppStrings.localized("quickStart.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        let ordered = store.tasks.map(\.id).filter { selectedIDs.contains($0) }
                        onSave(ordered)
                        dismiss()
                    }
                }
            }
        }
        .platformSheetFrame(width: 420, height: 520)
    }
}
