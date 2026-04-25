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
                    .disabled(store.taskEditorDraft != nil || store.manualTimeDraft != nil)

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
            DesktopMainView(store: store)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
        List(selection: $store.selectedTaskID) {
            Section {
                SidebarStaticRow(title: "Today", systemImage: "sun.max", count: store.activeSegments.count, color: .blue)
                SidebarStaticRow(title: "收件箱", systemImage: "tray", count: 3, color: .primary)
                SidebarStaticRow(title: "收藏", systemImage: "star", count: 2, color: .primary)
            }

            Section("任务") {
                ForEach(store.rootTasks(), id: \.id) { task in
                    TaskTreeRow(store: store, task: task)
                        .tag(task.id)
                }
            }

            Section("Areas") {
                SidebarStaticRow(title: "工作", systemImage: "target", count: 7, color: .blue)
                SidebarStaticRow(title: "学习", systemImage: "target", count: 5, color: .blue)
                SidebarStaticRow(title: "生活", systemImage: "target", count: 2, color: .blue)
            }

            Section("Tags") {
                SidebarStaticRow(title: "深度工作", systemImage: "tag", count: 4, color: .red)
                SidebarStaticRow(title: "会议", systemImage: "tag", count: 3, color: .red)
                SidebarStaticRow(title: "阅读", systemImage: "tag", count: 3, color: .red)
            }
        }
        .navigationTitle("Time Tracker")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: "gearshape")
                Text("设置")
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding()
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
                InfoRow(title: "本周", value: DurationFormatter.compact(store.secondsForTaskToday(task) + 2 * 3600 + 16 * 60))
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
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
            Text(task.notes ?? "完善三栏布局，强调时间线与 Inspector 的配合。")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
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
                SmallStat(title: "平均专注", value: DurationFormatter.compact(max(27 * 60, store.averageFocusSeconds)))
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
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
                ForEach(store.timelineSegments.filter { $0.taskID == task.id }.prefix(2), id: \.id) { segment in
                    HStack {
                        Text(shortRange(segment))
                        Spacer()
                        Text(DurationFormatter.compact(Int((segment.endedAt ?? Date()).timeIntervalSince(segment.startedAt))))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.monospacedDigit())
                }

                HStack {
                    Text("查看全部 (6)")
                        .foregroundStyle(.blue)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
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
                    SmallStat(title: "本周", value: DurationFormatter.compact(store.secondsForTaskToday(task) + 2 * 3600 + 16 * 60))
                }

                Text(task.notes ?? "完善三栏布局，强调时间线与 Inspector 的配合。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
        }
    }
}

struct TasksView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        List {
            ForEach(store.rootTasks(), id: \.id) { task in
                Section(task.title) {
                    ForEach(store.children(of: task), id: \.id) { child in
                        Button {
                            store.selectedTaskID = child.id
                        } label: {
                            HStack {
                                TaskIcon(task: child, size: 28)
                                Text(child.title)
                                Spacer()
                                Text(DurationFormatter.compact(store.secondsForTaskToday(child)))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .swipeActions {
                            Button {
                                store.startTask(child)
                            } label: {
                                Label("开始", systemImage: "play.fill")
                            }
                            .tint(.blue)

                            Button {
                                store.presentEditTask(child)
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.gray)
                        }
                    }
                }
            }
        }
        .navigationTitle("任务")
        .toolbar {
            Button {
                store.presentNewTask()
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

struct PomodoroView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(store.selectedTask?.title ?? "选择任务")
                .font(.title2.weight(.semibold))

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: 0.67)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("25:00")
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 230, height: 230)

            Button {
                store.startPomodoroForSelectedTask()
            } label: {
                Label("开始专注", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 36)

            Spacer()
        }
        .navigationTitle("番茄钟")
        .background(AppColors.background)
    }
}

struct AnalyticsView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("概览")
                    .font(.largeTitle.bold())

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        AnalyticsMetric(title: "Wall Time", value: DurationFormatter.compact(store.todayWallSeconds(now: context.date)), delta: "+12%")
                        AnalyticsMetric(title: "Gross Time", value: DurationFormatter.compact(store.todayGrossSeconds(now: context.date)), delta: "+18%")
                        AnalyticsMetric(title: "Overlap", value: DurationFormatter.compact(store.overlapSeconds(now: context.date)), delta: "透明")
                        AnalyticsMetric(title: "番茄", value: "\(store.completedPomodoroCount)", delta: "+2")
                    }
                }

                VStack(alignment: .leading) {
                    Text("任务分布")
                        .font(.headline)
                    Chart(store.tasks.filter { store.secondsForTaskToday($0) > 0 }, id: \.id) { task in
                        BarMark(
                            x: .value("Time", store.secondsForTaskToday(task) / 60),
                            y: .value("Task", task.title)
                        )
                        .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
                    }
                    .frame(height: 260)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
            }
            .padding()
        }
        .navigationTitle("分析")
        .background(AppColors.background)
    }
}

struct AnalyticsMetric: View {
    let title: String
    let value: String
    let delta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(delta)
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
    }
}

struct SettingsView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        Form {
            Section("数据") {
                LabeledContent("本地优先", value: "SwiftData")
                LabeledContent("事实来源", value: "TimeSegment")
                LabeledContent("同步字段", value: "deviceID / clientMutationID")
            }

            Section("操作") {
                Button("手动补录 30 分钟") {
                    store.presentManualTime()
                }
            }
        }
        .navigationTitle("设置")
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
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.taskEditorDraft?.id)
        .animation(.easeOut(duration: 0.16), value: store.manualTimeDraft?.id)
    }

    private var modalBackdrop: some View {
        Color.black.opacity(0.18)
            .ignoresSafeArea()
            .onTapGesture {
                store.taskEditorDraft = nil
                store.manualTimeDraft = nil
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppColors.border))
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
