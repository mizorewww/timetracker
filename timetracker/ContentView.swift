import Charts
import Foundation
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
private struct NewTaskActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ManualTimeActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct StartTimerActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct StartPomodoroActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RefreshActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newTaskAction: (() -> Void)? {
        get { self[NewTaskActionKey.self] }
        set { self[NewTaskActionKey.self] = newValue }
    }

    var manualTimeAction: (() -> Void)? {
        get { self[ManualTimeActionKey.self] }
        set { self[ManualTimeActionKey.self] = newValue }
    }

    var startTimerAction: (() -> Void)? {
        get { self[StartTimerActionKey.self] }
        set { self[StartTimerActionKey.self] = newValue }
    }

    var startPomodoroAction: (() -> Void)? {
        get { self[StartPomodoroActionKey.self] }
        set { self[StartPomodoroActionKey.self] = newValue }
    }

    var refreshAction: (() -> Void)? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
}
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var store = TimeTrackerStore()

    var body: some View {
        Group {
            #if os(macOS)
            ZStack {
                DesktopRootView(store: store)
                    .disabled(store.taskEditorDraft != nil || store.manualTimeDraft != nil || store.segmentEditorDraft != nil)

                DesktopModalLayer(store: store)
            }
            #else
            iOSRootView(store: store)
            #endif
        }
        .task {
            store.configureIfNeeded(context: modelContext)
        }
        .alert("Error", isPresented: errorBinding) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        #if os(iOS)
        .sheet(item: $store.taskEditorDraft) { draft in
            TaskEditorSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $store.manualTimeDraft) { draft in
            ManualTimeSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $store.segmentEditorDraft) { draft in
            SegmentEditorSheet(store: store, initialDraft: draft)
        }
        #endif
        #if os(macOS)
        .focusedSceneValue(\.newTaskAction) {
            store.presentNewTask()
        }
        .focusedSceneValue(\.manualTimeAction) {
            store.presentManualTime()
        }
        .focusedSceneValue(\.startTimerAction) {
            store.startSelectedTask()
        }
        .focusedSceneValue(\.startPomodoroAction) {
            store.startPomodoroForSelectedTask()
        }
        .focusedSceneValue(\.refreshAction) {
            store.refreshQuietly()
        }
        #endif
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            store.errorMessage != nil
        } set: { newValue in
            if !newValue {
                store.errorMessage = nil
            }
        }
    }
}

#if os(iOS)
struct iOSRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            DesktopRootView(store: store)
        } else {
            TabView {
                NavigationStack {
                    PhoneHomeView(store: store)
                }
                .tabItem { Label("首页", systemImage: "house.fill") }

                NavigationStack {
                    TasksView(store: store)
                }
                .tabItem { Label("任务", systemImage: "list.bullet") }

                NavigationStack {
                    PomodoroView(store: store)
                }
                .tabItem { Label("番茄钟", systemImage: "timer") }

                NavigationStack {
                    AnalyticsView(store: store)
                }
                .tabItem { Label("分析", systemImage: "chart.bar.xaxis") }

                NavigationStack {
                    SettingsView(store: store)
                }
                .tabItem { Label("设置", systemImage: "gearshape") }
            }
        }
    }
}
#endif

struct DesktopRootView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 270)
                #endif
        } content: {
            DesktopContentView(store: store)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 620, ideal: 720)
                #endif
        } detail: {
            InspectorView(store: store)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 280)
                #endif
        }
    }
}

struct DesktopContentView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        switch store.desktopDestination {
        case .today:
            DesktopMainView(store: store)
        case .tasks:
            TasksView(store: store)
        case .pomodoro:
            PomodoroView(store: store)
        case .analytics:
            AnalyticsView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }
}

struct DesktopMainView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 720
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 16 : 22) {
                    HeaderBar(store: store, compact: compact)
                    MetricsAndActions(store: store, horizontal: !compact)
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
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.presentNewTask()
                } label: {
                    Label("新建", systemImage: "plus")
                }

                Button {
                    store.presentManualTime()
                } label: {
                    Label("补录", systemImage: "calendar.badge.plus")
                }

                Button {
                    store.refreshQuietly()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
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
                HeaderBar(store: store, compact: true)
                MetricsAndActions(store: store, horizontal: false)
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
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: phoneToolbarPlacement) {
                Button {
                } label: {
                    Image(systemName: "magnifyingglass")
                }

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
        VStack(alignment: .leading, spacing: 12) {
            if !compact {
                HStack(spacing: 16) {
                    Text("Today")
                        .font(.largeTitle.bold())

                    Spacer()

                    Picker("Range", selection: $store.selectedRange) {
                        ForEach(TimeTrackerStore.RangePreset.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }
            } else {
                Picker("Range", selection: $store.selectedRange) {
                    ForEach(TimeTrackerStore.RangePreset.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

struct MetricsAndActions: View {
    @ObservedObject var store: TimeTrackerStore
    let horizontal: Bool

    var body: some View {
        Group {
            if horizontal {
                HStack(alignment: .top, spacing: 18) {
                    MetricsPanel(store: store)
                    ActionStack(store: store)
                        .frame(width: 220)
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

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    MetricCell(title: "今日追踪", value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .blue, isMuted: false, values: [3, 4, 8, 5, 11, 6, 4, 7, 5, 9, 10], showsBars: true)
                    Divider()
                    MetricCell(title: "Wall Time", value: DurationFormatter.compact(store.todayWallSeconds(now: context.date)), tint: .gray, isMuted: true, values: [1, 3, 6, 2, 7, 4, 3, 5, 8, 4, 6], showsBars: true)
                    Divider()
                    MetricCell(title: "Gross Time", value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .gray, isMuted: true, values: [2, 5, 7, 4, 9, 8, 3, 5, 8, 11, 6], showsBars: true)
                }

                VStack(spacing: 12) {
                    MetricCell(title: "今日追踪", value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .blue, isMuted: false, values: [], showsBars: false)
                    Divider()
                    HStack(spacing: 0) {
                        MetricCell(title: "Wall Time", value: DurationFormatter.compact(store.todayWallSeconds(now: context.date)), tint: .gray, isMuted: true, values: [], showsBars: false)
                        Divider()
                        MetricCell(title: "Gross Time", value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), tint: .gray, isMuted: true, values: [], showsBars: false)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColors.border)
        )
    }
}

struct MetricCell: View {
    let title: String
    let value: String
    let tint: Color
    let isMuted: Bool
    let values: [Int]
    var showsBars: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(isMuted ? Color.clear : tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isMuted ? .primary : tint)
            }

            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.8)

            if showsBars {
                MiniBars(values: values, tint: isMuted ? .gray.opacity(0.38) : tint)
                    .frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
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

    var body: some View {
        VStack(spacing: 12) {
            Button {
                store.startSelectedTask()
            } label: {
                Label("开始计时", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("home.startTimer")

            Button {
                store.presentNewTask()
            } label: {
                Label("新建任务", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("home.newTask")
        }
    }
}

struct ActiveTimersSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Active Timers", trailing: store.activeSegments.isEmpty ? nil : "全部")

            VStack(spacing: 0) {
                if store.activeSegments.isEmpty {
                    EmptyStateRow(title: "没有正在运行的计时", icon: "pause.circle")
                } else {
                    ForEach(store.activeSegments, id: \.id) { segment in
                        ActiveTimerRow(store: store, segment: segment)
                        if segment.id != store.activeSegments.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.border)
            )
        }
    }
}

struct PausedSessionsSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        if !store.pausedSessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Paused Sessions")

                VStack(spacing: 0) {
                    ForEach(store.pausedSessions, id: \.id) { session in
                        PausedSessionRow(store: store, session: session)
                        if session.id != store.pausedSessions.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColors.border)
                )
            }
        }
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
                Text(store.task(for: session.taskID)?.title ?? "Deleted Task")
                    .font(.headline)
                Text("已暂停")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.resume(session: session)
            } label: {
                Label("恢复", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)

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
            store.selectedTaskID = session.taskID
        }
        .padding(14)
    }
}

struct ActiveTimerRow: View {
    @ObservedObject var store: TimeTrackerStore
    let segment: TimeSegment

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                .frame(width: 10, height: 10)

            TaskIcon(task: store.task(for: segment.taskID))

            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayTitle(for: segment))
                    .font(.headline)
                Text(store.displayPath(for: segment))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.65)

            Button {
                store.pause(segment: segment)
            } label: {
                Image(systemName: "pause.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                store.stop(segment: segment)
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedTaskID = segment.taskID
        }
        .padding(14)
    }
}

struct TimelineSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Today Timeline")

            VStack(spacing: 0) {
                if store.timelineSegments.isEmpty {
                    EmptyStateRow(title: "今天还没有时间片段", icon: "clock")
                } else {
                    ForEach(store.timelineSegments, id: \.id) { segment in
                        TimelineRow(store: store, segment: segment)
                        if segment.id != store.timelineSegments.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColors.border)
            )
        }
    }
}

struct TimelineRow: View {
    @ObservedObject var store: TimeTrackerStore
    let segment: TimeSegment

    private var tag: String {
        switch segment.source {
        case .pomodoro: return "Pomodoro"
        case .manual: return "Manual"
        default: return store.task(for: segment.taskID)?.title.contains("阅读") == true ? "阅读" : "Timer"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                .frame(width: 9, height: 9)

            Text(timeRangeText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(store.displayTitle(for: segment))
                .lineLimit(1)

            Spacer()

            Text(tag)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(tagColor)
                .background(tagColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            if segment.endedAt == nil {
                Text("now")
                    .foregroundStyle(.blue)
                    .font(.subheadline.monospacedDigit())
            } else {
                Text(DurationFormatter.compact(Int((segment.endedAt ?? Date()).timeIntervalSince(segment.startedAt))))
                    .foregroundStyle(.secondary)
                    .font(.subheadline.monospacedDigit())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedTaskID = segment.taskID
        }
        .contextMenu {
            Button {
                store.presentEditSegment(segment)
            } label: {
                Label("编辑时间片段", systemImage: "pencil")
            }

            Button {
                store.presentManualTime(taskID: segment.taskID)
            } label: {
                Label("补录同类任务", systemImage: "calendar.badge.plus")
            }

            Divider()

            Button(role: .destructive) {
                store.deleteSegment(segment.id)
            } label: {
                Label("软删除时间片段", systemImage: "trash")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var tagColor: Color {
        switch tag {
        case "Pomodoro": return .blue
        case "Manual": return .orange
        case "阅读": return .green
        default: return .secondary
        }
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: segment.startedAt)
        let end = segment.endedAt.map { formatter.string(from: $0) } ?? "Now"
        return "\(start) - \(end)"
    }
}

struct QuickStartSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Quick Start")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(store.recentTasks, id: \.id) { task in
                    Button {
                        store.startTask(task)
                    } label: {
                        Label(task.title, systemImage: task.iconName ?? "play")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Button {
                    store.presentNewTask()
                } label: {
                    Label("新建任务", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

struct SidebarView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        List {
            Section {
                ForEach(TimeTrackerStore.DesktopDestination.allCases) { destination in
                    SidebarDestinationRow(
                        destination: destination,
                        count: count(for: destination),
                        isSelected: store.desktopDestination == destination
                    ) {
                        store.desktopDestination = destination
                    }
                    .accessibilityIdentifier("sidebar.\(destination.rawValue)")
                }
            }

            Section("任务") {
                ForEach(store.rootTasks(), id: \.id) { task in
                    TaskTreeRow(store: store, task: task)
                        .tag(task.id)
                }
            }
        }
        .navigationTitle("Time Tracker")
    }

    private func count(for destination: TimeTrackerStore.DesktopDestination) -> Int? {
        switch destination {
        case .today:
            return store.activeSegments.count
        case .tasks:
            return store.tasks.count
        case .pomodoro:
            return store.pomodoroRuns.filter { $0.state == .completed }.count
        case .analytics:
            return nil
        case .settings:
            return nil
        }
    }
}

struct TaskTreeRow: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        let children = store.children(of: task)
        Group {
            if children.isEmpty {
                taskLabel
                    .tag(task.id)
            } else {
                DisclosureGroup {
                    ForEach(children, id: \.id) { child in
                        TaskTreeRow(store: store, task: child)
                            .tag(child.id)
                    }
                } label: {
                    taskLabel
                }
            }
        }
    }

    private var taskLabel: some View {
        HStack {
            Image(systemName: task.iconName ?? "checkmark.circle")
                .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
            Text(task.title)
            Spacer()
            let childCount = store.children(of: task).count
            if childCount > 0 {
                Text("\(childCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedTaskID = task.id
        }
        .contextMenu {
            TaskContextMenu(store: store, task: task)
        }
    }
}

struct TaskContextMenu: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        Button {
            store.startTask(task)
        } label: {
            Label("开始计时", systemImage: "play.fill")
        }

        Button {
            store.presentNewTask(parentID: task.id)
        } label: {
            Label("新建子任务", systemImage: "plus")
        }

        Button {
            store.presentManualTime(taskID: task.id)
        } label: {
            Label("手动补录", systemImage: "calendar.badge.plus")
        }

        Divider()

        Button {
            store.presentEditTask(task)
        } label: {
            Label("编辑", systemImage: "pencil")
        }

        Button {
            store.archiveSelectedTask(taskID: task.id)
        } label: {
            Label("归档", systemImage: "archivebox")
        }

        Button(role: .destructive) {
            store.deleteSelectedTask(taskID: task.id)
        } label: {
            Label("软删除", systemImage: "trash")
        }
    }
}

struct SidebarStaticRow: View {
    let title: String
    let systemImage: String
    let count: Int
    let color: Color

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(color)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }
}

struct SidebarDestinationRow: View {
    let destination: TimeTrackerStore.DesktopDestination
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(destination.title, systemImage: destination.symbolName)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

struct InspectorView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Selected Task")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "pin")
                        .foregroundStyle(.secondary)
                }

                if let task = store.selectedTask {
                    SelectedTaskHeader(store: store, task: task)
                    InspectorInfoGrid(store: store, task: task)
                    NotesPanel(task: task)
                    StatsPanel(store: store, task: task)
                    PomodoroSettingsPanel(store: store)
                    RecentSessionsPanel(store: store, task: task)
                    InspectorActionButtons(store: store)
                } else {
                    EmptyStateRow(title: "选择一个任务", icon: "cursorarrow.click")
                }
            }
            .padding(20)
        }
        .background(AppColors.background)
    }
}

struct SelectedTaskHeader: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: task.colorHex) ?? .blue)
                .frame(width: 10, height: 10)
            Text(task.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Spacer()
            Button {
                store.presentEditTask(task)
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct InspectorInfoGrid: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("基本信息")
                .font(.headline)

            VStack(spacing: 10) {
                InfoRow(title: "路径", value: store.path(for: task))
                InfoRow(title: "状态", value: activeStatusText, badge: activeStatusText == "Running")
                InfoRow(title: "今日", value: DurationFormatter.compact(store.secondsForTaskToday(task)))
                InfoRow(title: "本周", value: DurationFormatter.compact(store.secondsForTaskThisWeek(task)))
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
        }
    }

    private var activeStatusText: String {
        store.activeSegments.contains { $0.taskID == task.id } ? "Running" : task.status.rawValue.capitalized
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var badge: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Spacer()
            Text(value)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .font(badge ? .caption.weight(.medium) : .subheadline)
                .foregroundStyle(badge ? .green : .primary)
                .padding(.horizontal, badge ? 8 : 0)
                .padding(.vertical, badge ? 4 : 0)
                .background(badge ? Color.green.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .font(.subheadline)
    }
}

struct NotesPanel: View {
    let task: TaskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            Text(task.notes ?? "没有备注")
                .foregroundStyle(task.notes == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
        }
    }
}

struct StatsPanel: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stats")
                .font(.headline)

            HStack {
                SmallStat(title: "今日番茄", value: "\(store.completedPomodoroCount)")
                Divider()
                SmallStat(title: "平均专注", value: DurationFormatter.compact(store.averageFocusSeconds))
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
            .accessibilityIdentifier("pomodoro.active")
        }
    }
}

struct SmallStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

struct PomodoroSettingsPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var autoBreak = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pomodoro Settings")
                .font(.headline)

            VStack(spacing: 12) {
                InfoRow(title: "专注时长", value: "25 分钟")
                InfoRow(title: "休息时长", value: "5 分钟")
                Toggle("专注结束后自动开始休息", isOn: $autoBreak)
                    .font(.subheadline)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
        }
    }
}

struct RecentSessionsPanel: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Sessions")
                .font(.headline)

            VStack(spacing: 8) {
                let recent = store.recentSegments(for: task, limit: 4)
                if recent.isEmpty {
                    EmptyStateRow(title: "还没有记录", icon: "clock")
                }

                ForEach(recent, id: \.id) { segment in
                    HStack {
                        Text(shortRange(segment))
                        Spacer()
                        Text(DurationFormatter.compact(Int((segment.endedAt ?? Date()).timeIntervalSince(segment.startedAt))))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.monospacedDigit())
                }

                if store.recentSegments(for: task, limit: 100).count > recent.count {
                    Text("还有更多记录")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
        }
    }

    private func shortRange(_ segment: TimeSegment) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: segment.startedAt)) - \(segment.endedAt.map { formatter.string(from: $0) } ?? "Now")"
    }
}

struct InspectorActionButtons: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(spacing: 10) {
            Button {
                store.startPomodoroForSelectedTask()
            } label: {
                Text("开始番茄钟")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(role: .destructive) {
                if let segment = store.activeSegments.first(where: { $0.taskID == store.selectedTaskID }) {
                    store.stop(segment: segment)
                }
            } label: {
                Label("停止计时", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                Button {
                    if let task = store.selectedTask {
                        store.presentEditTask(task)
                    }
                } label: {
                    Label("编辑", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    store.archiveSelectedTask()
                } label: {
                    Label("归档", systemImage: "archivebox")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                store.deleteSelectedTask()
            } label: {
                Label("软删除任务", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

struct InspectorSummaryCard: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        if let task = store.selectedTask {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("任务快照", systemImage: "smallcircle.filled.circle")
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(store.activeSegments.contains { $0.taskID == task.id } ? "Running" : task.status.rawValue.capitalized)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                Text(task.title)
                    .font(.title3.weight(.semibold))
                Text(store.path(for: task))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    SmallStat(title: "今日", value: DurationFormatter.compact(store.secondsForTaskToday(task)))
                    Divider()
                    SmallStat(title: "本周", value: DurationFormatter.compact(store.secondsForTaskThisWeek(task)))
                }

                Text(task.notes ?? "没有备注")
                    .font(.subheadline)
                    .foregroundStyle(task.notes == nil ? .secondary : .primary)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
        }
    }
}

struct TasksView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var searchText = ""

    private var searchResults: [TaskNode] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return store.tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(trimmed) ||
            store.path(for: task).localizedCaseInsensitiveContains(trimmed) ||
            (task.notes?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        List {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    ForEach(store.rootTasks(), id: \.id) { task in
                        TaskManagementTreeRow(store: store, task: task, depth: 0)
                    }
                } header: {
                    Text("任务树")
                } footer: {
                    Text("所有任务都可以计时，也都可以包含子任务。")
                }
            } else if searchResults.isEmpty {
                EmptyStateRow(title: "没有匹配的任务", icon: "magnifyingglass")
            } else {
                Section("搜索结果") {
                    ForEach(searchResults, id: \.id) { task in
                        TaskManagementFlatRow(store: store, task: task)
                    }
                }
            }

            Section {
                Button {
                    store.presentNewTask()
                } label: {
                    Label("新建根任务", systemImage: "plus")
                }
            }
        }
        .navigationTitle("任务")
        .searchable(text: $searchText, prompt: "搜索任务、路径或备注")
        .toolbar {
            Button {
                store.presentNewTask()
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

struct TaskManagementTreeRow: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    let depth: Int

    var body: some View {
        let children = store.children(of: task)
        Group {
            if children.isEmpty {
                TaskManagementFlatRow(store: store, task: task, depth: depth)
            } else {
                DisclosureGroup {
                    ForEach(children, id: \.id) { child in
                        TaskManagementTreeRow(store: store, task: child, depth: depth + 1)
                    }
                } label: {
                    TaskManagementFlatRow(store: store, task: task, depth: depth)
                }
            }
        }
    }
}

struct TaskManagementFlatRow: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    var depth: Int = 0

    private var isRunning: Bool {
        store.activeSegments.contains { $0.taskID == task.id }
    }

    var body: some View {
        Button {
            store.selectedTaskID = task.id
        } label: {
            HStack(spacing: 12) {
                TaskIcon(task: task, size: 30)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(task.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if isRunning {
                            Text("Running")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }

                    Text(store.path(for: task))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(DurationFormatter.compact(store.secondsForTaskToday(task)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    let childCount = store.children(of: task).count
                    if childCount > 0 {
                        Text("\(childCount) 子任务")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.leading, CGFloat(depth) * 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .contextMenu {
            TaskContextMenu(store: store, task: task)
        }
        .swipeActions(edge: .leading) {
            Button {
                store.startTask(task)
            } label: {
                Label("开始", systemImage: "play.fill")
            }
            .tint(.blue)

            Button {
                store.presentNewTask(parentID: task.id)
            } label: {
                Label("子任务", systemImage: "plus")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button {
                store.presentEditTask(task)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.gray)

            Button(role: .destructive) {
                store.deleteSelectedTask(taskID: task.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

struct PomodoroView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var preset: PomodoroPreset = .classic
    @State private var targetRounds = 1

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header

                if let run = store.activePomodoroRun {
                    ActivePomodoroCard(store: store, run: run)
                } else {
                    PomodoroSetupCard(store: store, preset: $preset, targetRounds: $targetRounds)
                }

                PomodoroLedgerCard(store: store)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle("番茄钟")
        .background(AppColors.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("番茄钟")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("pomodoro.title")
            Text("专注时间会写入同一套 TimeSession / TimeSegment 账本。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum PomodoroPreset: String, CaseIterable, Identifiable {
    case classic = "25 / 5"
    case deep = "50 / 10"
    case quick = "15 / 3"

    var id: String { rawValue }

    var focusSeconds: Int {
        switch self {
        case .classic: return 25 * 60
        case .deep: return 50 * 60
        case .quick: return 15 * 60
        }
    }

    var breakSeconds: Int {
        switch self {
        case .classic: return 5 * 60
        case .deep: return 10 * 60
        case .quick: return 3 * 60
        }
    }

    var title: String {
        switch self {
        case .classic: return "经典专注"
        case .deep: return "深度工作"
        case .quick: return "快速进入"
        }
    }
}

private struct PomodoroSetupCard: View {
    @ObservedObject var store: TimeTrackerStore
    @Binding var preset: PomodoroPreset
    @Binding var targetRounds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("开始前")
                    .font(.headline)
                Text("请选择任务。番茄钟不是孤立倒计时，完成后会生成真实时间记录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("任务", selection: Binding<UUID?>(
                get: { store.selectedTaskID },
                set: { store.selectedTaskID = $0 }
            )) {
                Text("选择任务").tag(UUID?.none)
                ForEach(store.tasks) { task in
                    Text(store.path(for: task)).tag(Optional(task.id))
                }
            }

            Picker("模式", selection: $preset) {
                ForEach(PomodoroPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Stepper(value: $targetRounds, in: 1...8) {
                LabeledContent("目标轮次", value: "\(targetRounds)")
            }

            HStack {
                PomodoroPlanMetric(title: "专注", value: DurationFormatter.compact(preset.focusSeconds))
                PomodoroPlanMetric(title: "休息", value: DurationFormatter.compact(preset.breakSeconds))
                PomodoroPlanMetric(title: "模式", value: preset.title)
            }

            Button {
                store.startPomodoroForSelectedTask(
                    focusSeconds: preset.focusSeconds,
                    breakSeconds: preset.breakSeconds,
                    targetRounds: targetRounds
                )
            } label: {
                Label("开始专注", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.selectedTaskID == nil)
            .accessibilityIdentifier("pomodoro.startFocus")
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
    }
}

private struct ActivePomodoroCard: View {
    @ObservedObject var store: TimeTrackerStore
    let run: PomodoroRun

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = store.pomodoroRemainingSeconds(for: run, now: context.date)
            let progress = store.pomodoroProgress(for: run, now: context.date)
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Label(store.pomodoroStateLabel(for: run), systemImage: run.state == .focusing ? "flame.fill" : "pause.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(run.state == .focusing ? .blue : .orange)
                    Text(store.taskTitle(for: run))
                        .font(.title2.weight(.semibold))
                    Text("\(run.completedFocusRounds) / \(run.targetRounds) 轮")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 6) {
                        Text(DurationFormatter.clock(remaining))
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(remaining == 0 ? "可以完成本轮" : "剩余时间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 240, height: 240)

                HStack(spacing: 12) {
                    Button {
                        store.completeActivePomodoro()
                    } label: {
                        Label(remaining == 0 ? "完成本轮" : "提前完成", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(role: .destructive) {
                        store.cancelActivePomodoro()
                    } label: {
                        Label("取消", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
            .accessibilityIdentifier("pomodoro.active")
        }
    }
}

private struct PomodoroPlanMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PomodoroLedgerCard: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近番茄")
                .font(.headline)

            if store.pomodoroRuns.isEmpty {
                EmptyStateRow(title: "还没有番茄钟记录", icon: "timer")
            } else {
                VStack(spacing: 0) {
                    ForEach(store.pomodoroRuns.prefix(5)) { run in
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: run.state))
                                .foregroundStyle(color(for: run.state))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.taskTitle(for: run))
                                    .font(.subheadline.weight(.medium))
                                Text("\(store.pomodoroStateLabel(for: run)) · \(run.completedFocusRounds)/\(run.targetRounds) 轮")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DurationFormatter.compact(run.focusSecondsPlanned))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)

                        if run.id != store.pomodoroRuns.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
    }

    private func iconName(for state: PomodoroState) -> String {
        switch state {
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .focusing: return "flame.fill"
        case .shortBreak, .longBreak: return "cup.and.saucer.fill"
        case .planned: return "timer"
        case .interrupted: return "pause.circle.fill"
        }
    }

    private func color(for state: PomodoroState) -> Color {
        switch state {
        case .completed: return .green
        case .cancelled: return .red
        case .focusing: return .blue
        case .shortBreak, .longBreak: return .orange
        case .planned, .interrupted: return .secondary
        }
    }
}

struct AnalyticsView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var range: AnalyticsRange = .today

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let overview = store.analyticsOverview(for: range, now: context.date)
            let daily = store.dailyBreakdown(range: range, now: context.date)
            let hourly = store.hourlyBreakdown(for: context.date, now: context.date)
            let tasks = store.taskBreakdown(range: range, now: context.date)
            let overlaps = store.overlapSegments(range: range, now: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("分析")
                                .font(.largeTitle.bold())
                            Text(range == .today ? "今天的时间如何流动，以及它被哪些任务占用。" : "按天复盘时间趋势、任务分布和重叠计时。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("Range", selection: $range) {
                            ForEach(AnalyticsRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                        AnalyticsMetric(title: "Wall Time", value: DurationFormatter.compact(overview.wallSeconds), footnote: "去重后的真实时间")
                        AnalyticsMetric(title: "Gross Time", value: DurationFormatter.compact(overview.grossSeconds), footnote: "任务时间相加")
                        AnalyticsMetric(title: "Overlap", value: DurationFormatter.compact(overview.overlapSeconds), footnote: "并行计时差值")
                        AnalyticsMetric(title: "Pomodoros", value: "\(overview.pomodoroCount)", footnote: "已完成专注片段")
                    }

                    if range == .today {
                        TodayActivityCard(hourly: hourly)
                        ScreenTimeBreakdownCard(tasks: tasks, totalSeconds: max(overview.grossSeconds, 1))
                    } else {
                        AnalyticsChartCard(title: "每日趋势", subtitle: "Week / Month 使用每日聚合；Today 会改用小时分布。") {
                            Chart(daily) { point in
                                BarMark(
                                    x: .value("Day", point.label),
                                    y: .value("Wall Minutes", point.wallSeconds / 60)
                                )
                                .foregroundStyle(.blue)

                                LineMark(
                                    x: .value("Day", point.label),
                                    y: .value("Gross Minutes", point.grossSeconds / 60)
                                )
                                .foregroundStyle(.green)
                                .symbol(.circle)
                            }
                            .chartYAxisLabel("分钟")
                            .frame(height: 240)
                        }
                    }

                    AnalyticsChartCard(title: "任务排行", subtitle: "按 Gross Time 排序，方便看清并行计时归属。") {
                        if tasks.isEmpty {
                            EmptyStateRow(title: "这个范围内还没有任务时间", icon: "chart.bar")
                        } else {
                            Chart(tasks.prefix(8).map { $0 }) { task in
                                BarMark(
                                    x: .value("Minutes", task.grossSeconds / 60),
                                    y: .value("Task", task.title)
                                )
                                .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
                            }
                            .chartXAxisLabel("Gross 分钟")
                            .frame(height: max(220, CGFloat(min(tasks.count, 8)) * 34))
                        }
                    }

                    AnalyticsChartCard(title: "Top Tasks", subtitle: "任务路径保留，避免改名或移动后失去上下文。") {
                        VStack(spacing: 0) {
                            if tasks.isEmpty {
                                EmptyStateRow(title: "暂无任务排行", icon: "list.number")
                            } else {
                                ForEach(tasks.prefix(6)) { task in
                                    AnalyticsTaskRow(task: task, totalSeconds: max(overview.grossSeconds, 1))
                                    if task.id != tasks.prefix(6).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    AnalyticsChartCard(title: "Overlapping Sessions", subtitle: "这里解释 Gross Time 比 Wall Time 多出来的部分。") {
                        VStack(spacing: 0) {
                            if overlaps.isEmpty {
                                EmptyStateRow(title: "没有发现并行计时", icon: "rectangle.2.swap")
                            } else {
                                ForEach(overlaps.prefix(6)) { overlap in
                                    OverlapRow(overlap: overlap)
                                    if overlap.id != overlaps.prefix(6).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("分析")
        .background(AppColors.background)
    }
}

struct AnalyticsMetric: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
    }
}

struct AnalyticsChartCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
    }
}

struct TodayActivityCard: View {
    let hourly: [HourlyAnalyticsPoint]

    var body: some View {
        AnalyticsChartCard(title: "今天时间分布", subtitle: "每根柱代表一个小时；蓝色是 Wall Time，浅色背景提示并行计时产生的 Gross Time。") {
            Chart(hourly) { point in
                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Gross Minutes", point.grossSeconds / 60),
                    width: .fixed(8)
                )
                .foregroundStyle(Color.blue.opacity(0.16))

                BarMark(
                    x: .value("Hour", point.hour),
                    y: .value("Wall Minutes", point.wallSeconds / 60),
                    width: .fixed(8)
                )
                .foregroundStyle(.blue)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(hour == 23 ? "24" : "\(hour)")
                        }
                    }
                }
            }
            .chartYAxisLabel("分钟")
            .frame(height: 220)
        }
    }
}

struct ScreenTimeBreakdownCard: View {
    let tasks: [TaskAnalyticsPoint]
    let totalSeconds: Int

    private var visibleTasks: [TaskAnalyticsPoint] {
        Array(tasks.prefix(6))
    }

    var body: some View {
        AnalyticsChartCard(title: "任务使用时间", subtitle: "类似屏幕使用时间：先看总量，再看颜色分段和任务列表。") {
            VStack(alignment: .leading, spacing: 14) {
                if tasks.isEmpty {
                    EmptyStateRow(title: "今天还没有任务时间", icon: "hourglass")
                } else {
                    screenTimeBar

                    VStack(spacing: 0) {
                        ForEach(visibleTasks) { task in
                            ScreenTimeTaskRow(task: task, totalSeconds: totalSeconds)
                            if task.id != visibleTasks.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var screenTimeBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(visibleTasks) { task in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: task.colorHex) ?? .blue)
                        .frame(width: segmentWidth(for: task, totalWidth: proxy.size.width))
                }
                if tasks.count > visibleTasks.count {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 20)
                }
            }
        }
        .frame(height: 16)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func segmentWidth(for task: TaskAnalyticsPoint, totalWidth: CGFloat) -> CGFloat {
        let ratio = CGFloat(task.grossSeconds) / CGFloat(max(totalSeconds, 1))
        return max(10, totalWidth * ratio)
    }
}

struct ScreenTimeTaskRow: View {
    let task: TaskAnalyticsPoint
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: task.colorHex) ?? .blue)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(task.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.compact(task.grossSeconds))
                    .font(.subheadline.monospacedDigit())
                Text("\(Int((Double(task.grossSeconds) / Double(max(totalSeconds, 1))) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct AnalyticsTaskRow: View {
    let task: TaskAnalyticsPoint
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: task.colorHex) ?? .blue)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                Text(task.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatter.compact(task.grossSeconds))
                    .font(.subheadline.monospacedDigit())
                Text("\(Int(Double(task.grossSeconds) / Double(totalSeconds) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct OverlapRow: View {
    let overlap: OverlapAnalyticsPoint

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.2.swap")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(overlap.firstTitle) + \(overlap.secondTitle)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(timeRangeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(DurationFormatter.compact(overlap.durationSeconds))
                .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 10)
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: overlap.start)) - \(endFormatter.string(from: overlap.end))"
    }
}

struct SettingsView: View {
    @ObservedObject var store: TimeTrackerStore
    @AppStorage("DefaultFocusMinutes") private var defaultFocusMinutes = 25
    @AppStorage("DefaultBreakMinutes") private var defaultBreakMinutes = 5
    @AppStorage("AllowParallelTimers") private var allowParallelTimers = true
    @AppStorage("ShowGrossAndWallTogether") private var showGrossAndWallTogether = true
    @State private var isResetConfirmationPresented = false

    var body: some View {
        let sync = store.syncStatus

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("settings.title")
                    Text("本地优先、可同步、可验证。设置项按系统偏好设置的方式排列，避免信息挤在一起。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                SettingsSectionCard(
                    title: "同步",
                    subtitle: sync.isCloudBacked ? "SwiftData 容器已以 CloudKit private database 打开。" : "当前使用本地存储；CloudKit 不可用时会自动回退。",
                    symbol: "icloud.fill",
                    tint: .blue
                ) {
                    SettingsValueRow(title: "存储", value: "SwiftData")
                    SettingsValueRow(title: "事实来源", value: "TimeSegment")
                    SettingsStatusRow(title: "当前模式", status: sync.storageStatusText, tint: sync.isCloudBacked ? .green : .orange)
                    SettingsStatusRow(title: "CloudKit 账号", status: sync.accountStatus, tint: sync.accountStatus == "Apple ID 可用" ? .green : .orange)
                    SettingsValueRow(title: "iCloud 容器", value: sync.containerIdentifier, monospaced: true)
                    SettingsValueRow(title: "设备 ID", value: sync.deviceID, monospaced: true)
                    if let error = sync.lastError {
                        SettingsValueRow(title: "同步回退原因", value: error, monospaced: false, isWarning: true)
                    }
                    HStack {
                        Spacer()
                        Button {
                            Task {
                                await store.refreshCloudAccountStatus()
                            }
                        } label: {
                            Label("重新检查 iCloud", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SettingsSectionCard(
                    title: "默认行为",
                    subtitle: "这些偏好只影响新开始的流程，不会重写已有账本。",
                    symbol: "slider.horizontal.3",
                    tint: .indigo
                ) {
                    SettingsControlRow(title: "默认专注时长") {
                        Stepper("\(defaultFocusMinutes) 分钟", value: $defaultFocusMinutes, in: 5...90, step: 5)
                            .labelsHidden()
                    }
                    SettingsControlRow(title: "默认休息时长") {
                        Stepper("\(defaultBreakMinutes) 分钟", value: $defaultBreakMinutes, in: 1...30, step: 1)
                            .labelsHidden()
                    }
                    SettingsControlRow(title: "允许多个任务同时计时") {
                        Toggle("", isOn: $allowParallelTimers)
                            .labelsHidden()
                    }
                    SettingsControlRow(title: "同时显示 Wall / Gross Time") {
                        Toggle("", isOn: $showGrossAndWallTogether)
                            .labelsHidden()
                    }
                }

                SettingsSectionCard(
                    title: "账本概览",
                    subtitle: "这些数字直接来自 SwiftData 原始记录，不是缓存摘要。",
                    symbol: "list.bullet.rectangle.portrait.fill",
                    tint: .teal
                ) {
                    SettingsValueRow(title: "任务数量", value: "\(store.tasks.count)")
                    SettingsValueRow(title: "时间片段", value: "\(store.allSegments.count)")
                    SettingsValueRow(title: "番茄钟记录", value: "\(store.pomodoroRuns.count)")
                    SettingsValueRow(title: "已归档任务", value: "\(store.archivedTasks.count)")
                }

                SettingsSectionCard(
                    title: "调试与演示",
                    subtitle: "演示数据用于验证首页、时间线、重叠统计和分析图表。",
                    symbol: "wrench.and.screwdriver.fill",
                    tint: .gray
                ) {
                    SettingsActionRow(
                        title: "手动补录时间",
                        detail: "创建 source = manual 的 TimeSession 和 TimeSegment。",
                        symbol: "calendar.badge.plus"
                    ) {
                        store.presentManualTime()
                    }

                    SettingsActionRow(
                        title: "重建演示数据",
                        detail: "覆盖当前本地数据并生成多日任务、番茄钟和重叠计时。",
                        symbol: "sparkles"
                    ) {
                        isResetConfirmationPresented = true
                    }
                }
            }
            .frame(maxWidth: 860, alignment: .leading)
            .padding(24)
        }
        .background(AppColors.background)
        .navigationTitle("设置")
        .confirmationDialog("重建演示数据？", isPresented: $isResetConfirmationPresented, titleVisibility: .visible) {
            Button("清空并生成演示数据", role: .destructive) {
                store.replaceWithDemoData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除当前本机 SwiftData 存储中的任务和时间片段，然后写入一组多日演示数据。")
        }
        .accessibilityIdentifier("settings.view")
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.gradient)
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    content
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
            }
        }
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String
    var monospaced = false
    var isWarning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title)
                .foregroundStyle(.primary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .body)
                .foregroundStyle(isWarning ? .orange : .secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 164)
        }
    }
}

struct SettingsStatusRow: View {
    let title: String
    let status: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .frame(width: 150, alignment: .leading)
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(tint.opacity(0.12), in: Capsule())
            Spacer()
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 164)
        }
    }
}

struct SettingsControlRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 18) {
            Text(title)
                .font(.subheadline)
                .frame(width: 220, alignment: .leading)
            Spacer()
            control
                .frame(minWidth: 120, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 234)
        }
    }
}

struct SettingsActionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, 50)
        }
    }
}

struct DesktopModalLayer: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        ZStack {
            if let draft = store.taskEditorDraft {
                modalBackdrop
                TaskEditorPanel(
                    store: store,
                    initialDraft: draft,
                    onCancel: { store.taskEditorDraft = nil },
                    onSave: { store.saveTaskDraft($0) }
                )
                .frame(width: 500, height: 560)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
            } else if let draft = store.manualTimeDraft {
                modalBackdrop
                ManualTimePanel(
                    store: store,
                    initialDraft: draft,
                    onCancel: { store.manualTimeDraft = nil },
                    onSave: { store.saveManualTimeDraft($0) }
                )
                .frame(width: 620, height: 520)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
            } else if let draft = store.segmentEditorDraft {
                modalBackdrop
                SegmentEditorPanel(
                    store: store,
                    initialDraft: draft,
                    onCancel: { store.segmentEditorDraft = nil },
                    onSave: { store.saveSegmentDraft($0) },
                    onDelete: { store.deleteSegment($0) }
                )
                .frame(width: 620, height: 560)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.taskEditorDraft?.id)
        .animation(.easeOut(duration: 0.16), value: store.manualTimeDraft?.id)
        .animation(.easeOut(duration: 0.16), value: store.segmentEditorDraft?.id)
    }

    private var modalBackdrop: some View {
        Color.black.opacity(0.18)
            .ignoresSafeArea()
            .onTapGesture {
                store.taskEditorDraft = nil
                store.manualTimeDraft = nil
                store.segmentEditorDraft = nil
            }
    }
}

struct TaskEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskEditorDraft

    var body: some View {
        TaskEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.taskEditorDraft = nil
                dismiss()
            },
            onSave: { draft in
                store.saveTaskDraft(draft)
                dismiss()
            }
        )
        .presentationDetents([.large])
    }
}

struct TaskEditorPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: TaskEditorDraft
    @State private var isSymbolPickerPresented = false
    let onCancel: () -> Void
    let onSave: (TaskEditorDraft) -> Void

    private let colors = ["1677FF", "16A34A", "7C3AED", "F97316", "EF4444", "0EA5E9", "64748B"]

    init(store: TimeTrackerStore, initialDraft: TaskEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (TaskEditorDraft) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.taskID == nil ? "新建任务" : "编辑任务")
                        .font(.title2.bold())
                    Text("任务可以计时，也可以继续包含子任务。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
            }
            .padding(18)

            Form {
                Section("基本信息") {
                    TextField("任务名称", text: $draft.title)

                    Picker("父任务", selection: parentBinding) {
                        Text("根级").tag(Optional<UUID>.none)
                        ForEach(store.tasks.filter { $0.id != draft.taskID }, id: \.id) { task in
                            Text(indentedTitle(task)).tag(Optional(task.id))
                        }
                    }

                    HStack {
                        Text("符号与颜色")
                        Spacer()
                        Button {
                            isSymbolPickerPresented = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: draft.iconName)
                                    .foregroundStyle(Color(hex: draft.colorHex) ?? .blue)
                                Text("选择")
                            }
                        }
                        .popover(isPresented: $isSymbolPickerPresented) {
                            SymbolAndColorPicker(
                                symbols: SymbolCatalog.symbolNames,
                                searchKeywords: SymbolCatalog.searchKeywords,
                                colors: colors,
                                symbolName: $draft.iconName,
                                colorHex: $draft.colorHex
                            )
                            .frame(width: 460, height: 520)
                            .padding()
                        }
                    }
                }

                Section("计划") {
                    Stepper(value: estimatedMinutesBinding, in: 0...600, step: 15) {
                        LabeledContent("预计时长", value: draft.estimatedMinutes.map { "\($0) 分钟" } ?? "未设置")
                    }

                    Toggle("设置截止日", isOn: $draft.hasDueDate)
                    if draft.hasDueDate {
                        DatePicker("截止日", selection: $draft.dueAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("备注") {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 88)
                }
            }
            .formStyle(.grouped)

            modalFooter(canSave: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private var parentTitle: String {
        guard let parentID = draft.parentID, let task = store.task(for: parentID) else {
            return "根级任务"
        }
        return store.path(for: task)
    }

    private var parentBinding: Binding<UUID?> {
        Binding {
            draft.parentID
        } set: { value in
            draft.parentID = value
        }
    }

    private var estimatedMinutesBinding: Binding<Int> {
        Binding {
            draft.estimatedMinutes ?? 0
        } set: { value in
            draft.estimatedMinutes = value == 0 ? nil : value
        }
    }

    private func indentedTitle(_ task: TaskNode) -> String {
        String(repeating: "  ", count: task.depth) + task.title
    }

    private func modalFooter(canSave: Bool) -> some View {
        HStack {
            Button("取消") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("保存") {
                onSave(draft)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
        .padding(18)
        .background(.thinMaterial)
    }
}

struct ManualTimeSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: ManualTimeDraft

    var body: some View {
        ManualTimePanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.manualTimeDraft = nil
                dismiss()
            },
            onSave: { draft in
                store.saveManualTimeDraft(draft)
                dismiss()
            }
        )
        .presentationDetents([.medium, .large])
    }
}

struct SegmentEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: SegmentEditorDraft

    var body: some View {
        SegmentEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.segmentEditorDraft = nil
                dismiss()
            },
            onSave: { draft in
                store.saveSegmentDraft(draft)
                dismiss()
            },
            onDelete: { segmentID in
                store.deleteSegment(segmentID)
                dismiss()
            }
        )
        .presentationDetents([.medium, .large])
    }
}

struct SegmentEditorPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: SegmentEditorDraft
    let onCancel: () -> Void
    let onSave: (SegmentEditorDraft) -> Void
    let onDelete: (UUID) -> Void

    init(
        store: TimeTrackerStore,
        initialDraft: SegmentEditorDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (SegmentEditorDraft) -> Void,
        onDelete: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("编辑时间片段")
                        .font(.title2.bold())
                    Text("这会直接修正原始时间账本。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
            }
            .padding(18)

            Form {
                Section("归属") {
                    Picker("任务", selection: taskBinding) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(store.tasks, id: \.id) { task in
                            Text(store.path(for: task)).tag(Optional(task.id))
                        }
                    }

                    LabeledContent("来源", value: draft.source.rawValue)
                }

                Section("时间") {
                    DatePicker("开始", selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    Toggle("正在进行", isOn: $draft.isActive)
                    if !draft.isActive {
                        DatePicker("结束", selection: $draft.endedAt, displayedComponents: [.date, .hourAndMinute])
                        LabeledContent("时长") {
                            Text(DurationFormatter.compact(Int(draft.endedAt.timeIntervalSince(draft.startedAt))))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(draft.endedAt > draft.startedAt ? Color.primary : Color.red)
                        }
                    }
                }

                Section("备注") {
                    TextField("这段时间的说明", text: $draft.note)
                }

                Section {
                    Button(role: .destructive) {
                        onDelete(draft.segmentID)
                    } label: {
                        Label("软删除时间片段", systemImage: "trash")
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.taskID == nil || (!draft.isActive && draft.endedAt <= draft.startedAt))
            }
            .padding(18)
            .background(.thinMaterial)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private var taskBinding: Binding<UUID?> {
        Binding {
            draft.taskID
        } set: { value in
            draft.taskID = value
        }
    }
}

struct SymbolAndColorPicker: View {
    let symbols: [String]
    let searchKeywords: [String: [String]]
    let colors: [String]
    @Binding var symbolName: String
    @Binding var colorHex: String
    @State private var searchText = ""

    private var filteredSymbols: [String] {
        guard !searchText.isEmpty else { return symbols }
        return symbols.filter { symbol in
            symbol.localizedCaseInsensitiveContains(searchText) ||
            (searchKeywords[symbol]?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SF Symbols")
                    .font(.headline)
                Spacer()
                Text("\(filteredSymbols.count) / \(symbols.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextField("搜索符号名称", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 8)], spacing: 8) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .foregroundStyle(symbolName == symbol ? .white : (Color(hex: colorHex) ?? .blue))
                                .frame(width: 38, height: 38)
                                .background(symbolName == symbol ? (Color(hex: colorHex) ?? .blue) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
            }
            .frame(maxHeight: 330)

            Divider()

            Text("颜色")
                .font(.headline)

            HStack(spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 26, height: 26)
                            .overlay {
                                if colorHex == hex {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

enum SymbolCatalog {
    static let symbolNames: [String] = {
        let loaded = loadSymbolOrder()
        if !loaded.isEmpty {
            return loaded
        }
        return fallbackSymbols
    }()

    static let searchKeywords: [String: [String]] = loadSearchKeywords()

    private static func loadSymbolOrder() -> [String] {
        for url in resourceURLs(fileName: "symbol_order", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let names = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String],
                  !names.isEmpty else {
                continue
            }
            return Array(NSOrderedSet(array: names).compactMap { $0 as? String })
        }
        return []
    }

    private static func loadSearchKeywords() -> [String: [String]] {
        for url in resourceURLs(fileName: "symbol_search", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let keywords = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] else {
                continue
            }
            return keywords
        }
        return [:]
    }

    private static func resourceURLs(fileName: String, extension ext: String) -> [URL] {
        [
            "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/CoreServices/CoreGlyphs.bundle/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphsPrivate.bundle/Contents/Resources"
        ].map {
            URL(fileURLWithPath: $0).appendingPathComponent(fileName).appendingPathExtension(ext)
        }
    }

    private static let fallbackSymbols = [
        "checkmark.circle", "folder", "briefcase", "book", "macwindow",
        "square.grid.2x2", "chevron.left.forwardslash.chevron.right",
        "person.2", "pencil.and.list.clipboard", "target", "calendar",
        "clock", "timer", "paintbrush", "chart.bar", "doc.text",
        "hammer", "lightbulb", "paperplane", "terminal", "keyboard",
        "graduationcap", "heart", "house", "cart", "creditcard",
        "briefcase.fill", "star", "tag", "tray", "archivebox", "trash",
        "play.fill", "pause.fill", "stop.fill", "plus", "magnifyingglass"
    ]
}

struct ManualTimePanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: ManualTimeDraft
    let onCancel: () -> Void
    let onSave: (ManualTimeDraft) -> Void

    init(store: TimeTrackerStore, initialDraft: ManualTimeDraft, onCancel: @escaping () -> Void, onSave: @escaping (ManualTimeDraft) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("手动补录")
                        .font(.title2.bold())
                    Text("修正遗忘的工作时间，仍然写入统一时间账本。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
            }
            .padding(18)

            Form {
                Section("归属") {
                    Picker("任务", selection: taskBinding) {
                        Text("请选择").tag(Optional<UUID>.none)
                        ForEach(store.tasks, id: \.id) { task in
                            Text(store.path(for: task)).tag(Optional(task.id))
                        }
                    }
                }

                Section("时间") {
                    DatePicker("开始", selection: $draft.startedAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束", selection: $draft.endedAt, displayedComponents: [.date, .hourAndMinute])
                    LabeledContent("时长") {
                        Text(DurationFormatter.compact(Int(draft.endedAt.timeIntervalSince(draft.startedAt))))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(draft.endedAt > draft.startedAt ? Color.primary : Color.red)
                    }
                }

                Section("备注") {
                    TextField("例如：会议、补录、客户沟通", text: $draft.note)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存") {
                    onSave(draft)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.taskID == nil || draft.endedAt <= draft.startedAt)
            }
            .padding(18)
            .background(.thinMaterial)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private var taskBinding: Binding<UUID?> {
        Binding {
            draft.taskID
        } set: { value in
            draft.taskID = value
        }
    }
}

struct FormSectionBox<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
    }
}

struct TaskIcon: View {
    let task: TaskNode?
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: task?.iconName ?? "checkmark.circle")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(Color(hex: task?.colorHex) ?? .blue)
            .frame(width: size, height: size)
            .background((Color(hex: task?.colorHex) ?? .blue).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(AppColors.border))
    }
}

struct DurationLabel: View {
    let startedAt: Date
    let endedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let end = endedAt ?? context.date
            Text(DurationFormatter.clock(Int(end.timeIntervalSince(startedAt))))
        }
    }
}

struct EmptyStateRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }
}

enum AppColors {
    static let background = Color(platformColor: .systemGroupedBackground)
    static let border = Color.primary.opacity(0.08)
    static let panelHeader = LinearGradient(
        colors: [Color.blue.opacity(0.10), Color.green.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let value = UInt64(sanitized, radix: 16) else { return nil }
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    init(platformColor: PlatformColor) {
        #if os(macOS)
        self.init(nsColor: platformColor)
        #else
        self.init(uiColor: platformColor)
        #endif
    }
}

#if os(macOS)
typealias PlatformColor = NSColor
extension PlatformColor {
    static var systemGroupedBackground: NSColor { NSColor.windowBackgroundColor }
}
#else
typealias PlatformColor = UIColor
#endif

private extension TimeTrackerStore {
    func refreshQuietly() {
        do {
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [TaskNode.self, TimeSession.self, TimeSegment.self, PomodoroRun.self, DailySummary.self], inMemory: true)
}
