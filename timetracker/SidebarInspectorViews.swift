import SwiftUI

enum SidebarSelection: Hashable {
    case destination(TimeTrackerStore.DesktopDestination)
    case task(UUID)
}

struct SidebarView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var selection: SidebarSelection?

    private var destinations: [TimeTrackerStore.DesktopDestination] {
        #if os(macOS)
        return TimeTrackerStore.DesktopDestination.allCases.filter { $0 != .settings }
        #else
        return TimeTrackerStore.DesktopDestination.allCases
        #endif
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(destinations) { destination in
                    SidebarDestinationLabel(destination: destination, count: count(for: destination))
                        .tag(SidebarSelection.destination(destination))
                        .accessibilityIdentifier("sidebar.\(destination.rawValue)")
                }
            }

            Section(AppStrings.tasks) {
                ForEach(store.rootTasks(), id: \.id) { task in
                    TaskTreeRow(store: store, task: task, selection: $selection)
                }
            }
        }
        .navigationTitle(AppStrings.localized("app.name"))
        .onAppear {
            syncSelectionFromStore()
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            switch newValue {
            case let .destination(destination):
                store.desktopDestination = destination
            case let .task(taskID):
                store.selectTask(taskID)
            }
        }
        .onChange(of: store.selectedTaskID) { _, _ in
            syncSelectionFromStore()
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("settings.open")
                .help(AppStrings.settings)
            }
        }
        #endif
    }

    private func syncSelectionFromStore() {
        if let selectedTaskID = store.selectedTaskID {
            selection = .task(selectedTaskID)
        } else {
            selection = .destination(store.desktopDestination)
        }
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
    @Binding var selection: SidebarSelection?
    @State private var isPulsing = false

    var body: some View {
        let children = store.children(of: task)
        Group {
            if children.isEmpty {
                taskLabel
                    .tag(SidebarSelection.task(task.id))
            } else {
                DisclosureGroup {
                    ForEach(children, id: \.id) { child in
                        TaskTreeRow(store: store, task: child, selection: $selection)
                    }
                } label: {
                    taskLabel
                }
                .tag(SidebarSelection.task(task.id))
            }
        }
    }

    private var taskLabel: some View {
        HStack {
            Image(systemName: task.status.symbolName)
                .font(.caption)
                .foregroundStyle(Color(hex: task.status.colorHex) ?? .secondary)
                .frame(width: 14)
                .help(task.status.displayName)
            Image(systemName: task.iconName ?? "checkmark.circle")
                .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
            Text(task.title)
                .strikethrough(task.status == .completed)
                .foregroundStyle(task.status == .completed ? .secondary : .primary)
            Spacer()
            let progress = store.checklistProgress(for: task.id)
            if progress.totalCount > 0 {
                Text(progress.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            let childCount = store.children(of: task).count
            if childCount > 0 {
                Text("\(childCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .scaleEffect(isPulsing ? 1.045 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isPulsing)
        .onChange(of: store.selectedTaskPulseToken) { _, _ in
            guard store.selectedTaskPulseID == task.id else { return }
            isPulsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                isPulsing = false
            }
        }
        .contextMenu {
            TaskContextMenu(store: store, task: task)
        }
    }
}

struct TaskStatusBadge: View {
    let status: TaskStatus

    var body: some View {
        Label(status.displayName, systemImage: status.symbolName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color(hex: status.colorHex) ?? .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((Color(hex: status.colorHex) ?? .secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct TaskContextMenu: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        Button {
            store.startTask(task)
        } label: {
            Label(AppStrings.localized("task.action.startTimer"), systemImage: "play.fill")
        }

        Button {
            store.presentNewTask(parentID: task.id)
        } label: {
            Label(AppStrings.localized("task.action.newSubtask"), systemImage: "plus")
        }

        Button {
            store.presentManualTime(taskID: task.id)
        } label: {
            Label(AppStrings.localized("task.action.addManualTime"), systemImage: "calendar.badge.plus")
        }

        Menu(AppStrings.localized("task.status.menu")) {
            ForEach(TaskStatus.editableCases, id: \.self) { status in
                Button {
                    store.setTaskStatus(status, taskID: task.id)
                } label: {
                    Label(status.displayName, systemImage: status.symbolName)
                }
            }
        }

        Divider()

        Button {
            store.presentEditTask(task)
        } label: {
            Label(AppStrings.edit, systemImage: "pencil")
        }

        Button {
            store.archiveSelectedTask(taskID: task.id)
        } label: {
            Label(AppStrings.localized("task.action.archive"), systemImage: "archivebox")
        }

        Button(role: .destructive) {
            store.deleteSelectedTask(taskID: task.id)
        } label: {
            Label(AppStrings.localized("task.action.softDelete"), systemImage: "trash")
        }
    }
}

struct SidebarDestinationLabel: View {
    let destination: TimeTrackerStore.DesktopDestination
    let count: Int?

    var body: some View {
        HStack {
            Label(destination.title, systemImage: destination.symbolName)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }
}

struct InspectorView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(.app("inspector.selectedTask"))
                    .font(.headline)

                if let task = store.selectedTask {
                    SelectedTaskHeader(store: store, task: task)
                    InspectorInfoGrid(store: store, task: task)
                    TaskChecklistPanel(store: store, task: task)
                    TaskForecastPanel(store: store, task: task)
                    NotesPanel(task: task)
                    StatsPanel(store: store, task: task)
                    PomodoroSettingsPanel(store: store)
                    RecentSessionsPanel(store: store, task: task)
                    InspectorActionButtons(store: store)
                } else {
                    EmptyStateRow(title: AppStrings.localized("task.empty.selectTask"), icon: "cursorarrow.click")
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
    @State private var isPulsing = false

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
        .scaleEffect(isPulsing ? 1.045 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isPulsing)
        .onChange(of: store.selectedTaskPulseToken) { _, _ in
            guard store.selectedTaskPulseID == task.id else { return }
            isPulsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                isPulsing = false
            }
        }
    }
}

struct InspectorInfoGrid: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.app("task.section.info"))
                .font(.headline)

            VStack(spacing: 10) {
                InfoRow(title: AppStrings.localized("task.field.path"), value: store.path(for: task))
                InfoRow(title: AppStrings.localized("task.field.status"), value: activeStatusText, badge: activeStatusText == AppStrings.running)
                InfoRow(title: AppStrings.localized("task.field.today"), value: DurationFormatter.compact(store.secondsForTaskToday(task)))
                InfoRow(title: AppStrings.localized("task.field.week"), value: DurationFormatter.compact(store.secondsForTaskThisWeek(task)))
            }
            .appCard(padding: 14)
        }
    }

    private var activeStatusText: String {
        store.activeSegments.contains { $0.taskID == task.id } ? AppStrings.running : task.status.displayName
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
                .frame(minWidth: 54, maxWidth: 86, alignment: .leading)
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

struct TaskChecklistPanel: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    private var items: [ChecklistItem] {
        store.checklistItems(for: task.id)
    }

    private var progress: ChecklistProgress {
        store.checklistProgress(for: task.id)
    }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(.app("checklist.title"))
                        .font(.headline)
                    Spacer()
                    Text(progress.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: progress.fraction)
                    ForEach(items.prefix(5), id: \.id) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isCompleted ? .green : .secondary)
                            Text(item.title)
                                .lineLimit(1)
                                .strikethrough(item.isCompleted)
                                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                            Spacer()
                        }
                        .font(.subheadline)
                    }
                    if items.count > 5 {
                        Text(String(format: AppStrings.localized("checklist.moreFormat"), items.count - 5))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .appCard(padding: 14)
            }
        }
    }
}

struct TaskForecastPanel: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        if let rollup = store.rollup(for: task.id) {
            VStack(alignment: .leading, spacing: 8) {
                Text(.app("forecast.panel.title"))
                    .font(.headline)

                VStack(spacing: 10) {
                    ForecastExplanationCallout()
                    InfoRow(title: AppStrings.localized("forecast.worked"), value: DurationFormatter.compact(rollup.workedSeconds))
                    InfoRow(title: AppStrings.localized("forecast.estimatedTotal"), value: estimateText(for: rollup))
                    InfoRow(title: AppStrings.localized("forecast.remaining"), value: remainingText(for: rollup))
                    InfoRow(title: AppStrings.localized("forecast.projectedDays"), value: daysText(for: rollup))
                    InfoRow(title: AppStrings.localized("forecast.confidence"), value: rollup.confidence.displayName)
                    Text(rollup.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .appCard(padding: 14)
            }
        }
    }

    private func estimateText(for rollup: TaskRollup) -> String {
        rollup.estimatedTotalSeconds.map(DurationFormatter.compact) ?? AppStrings.localized("forecast.noEstimate")
    }

    private func remainingText(for rollup: TaskRollup) -> String {
        rollup.remainingSeconds.map(DurationFormatter.compact) ?? AppStrings.localized("forecast.noEstimate")
    }

    private func daysText(for rollup: TaskRollup) -> String {
        guard let days = rollup.projectedDays else {
            return AppStrings.localized("forecast.noEstimate")
        }
        return String(format: AppStrings.localized("forecast.daysFormat"), days)
    }
}

struct NotesPanel: View {
    let task: TaskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.app("editor.task.notes"))
                .font(.headline)
            Text(task.notes ?? AppStrings.localized("task.notes.empty"))
                .foregroundStyle(task.notes == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(padding: 12)
        }
    }
}

struct StatsPanel: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.app("inspector.stats"))
                .font(.headline)

            HStack {
                SmallStat(title: AppStrings.localized("task.stats.todayPomodoros"), value: "\(store.completedPomodoroCount)")
                Divider()
                SmallStat(title: AppStrings.localized("task.stats.averageFocus"), value: DurationFormatter.compact(store.averageFocusSeconds))
            }
            .appCard(padding: 14)
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
            Text(.app("inspector.pomodoroSettings"))
                .font(.headline)

            VStack(spacing: 12) {
                InfoRow(title: AppStrings.localized("task.field.defaultMode"), value: PomodoroPreset(rawValue: store.preferences.pomodoroDefaultMode)?.title ?? AppStrings.localized("common.custom"))
                InfoRow(title: AppStrings.localized("task.field.focusDuration"), value: String(format: AppStrings.localized("common.minutes"), store.preferences.defaultFocusMinutes))
                InfoRow(title: AppStrings.localized("task.field.breakDuration"), value: String(format: AppStrings.localized("common.minutes"), store.preferences.defaultBreakMinutes))
                InfoRow(title: AppStrings.localized("task.field.defaultRounds"), value: "\(store.preferences.defaultPomodoroRounds)")
                Toggle(AppStrings.localized("task.autoStartBreak"), isOn: $autoBreak)
                    .font(.subheadline)
            }
            .appCard(padding: 14)
        }
    }
}

struct RecentSessionsPanel: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.app("inspector.recentSessions"))
                .font(.headline)

            VStack(spacing: 8) {
                let recent = store.recentSegments(for: task, limit: 4)
                if recent.isEmpty {
                    EmptyStateRow(title: AppStrings.localized("task.records.empty"), icon: "clock")
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
                    Text(.app("task.records.more"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .appCard(padding: 14)
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
        if let task = store.selectedTask {
            VStack(spacing: 10) {
                timerControls(for: task)
                pomodoroControls(for: task)

                HStack(spacing: 10) {
                    Button {
                        store.presentEditTask(task)
                    } label: {
            Label(AppStrings.edit, systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.archiveSelectedTask()
                    } label: {
            Label(AppStrings.localized("task.action.archive"), systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    store.deleteSelectedTask()
                } label: {
                    Label(AppStrings.localized("task.action.softDeleteTask"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func timerControls(for task: TaskNode) -> some View {
        if let segment = store.activeSegment(for: task.id) {
            HStack(spacing: 10) {
                Button {
                    store.pause(segment: segment)
                } label: {
                    Label(AppStrings.localized("timer.action.pause"), systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    store.stop(segment: segment)
                } label: {
                    Label(AppStrings.localized("timer.action.stop"), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else if let session = store.pausedSession(for: task.id) {
            HStack(spacing: 10) {
                Button {
                    store.resume(session: session)
                } label: {
                    Label(AppStrings.localized("timer.action.resume"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    store.stop(session: session)
                } label: {
                    Label(AppStrings.localized("timer.action.end"), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else {
            Button {
                store.startTask(task)
            } label: {
                Label(AppStrings.localized("task.action.startTimer"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func pomodoroControls(for task: TaskNode) -> some View {
        if let run = store.activePomodoroRun(for: task.id) {
            HStack(spacing: 10) {
                if run.state == .interrupted,
                   let sessionID = run.sessionID,
                   let session = store.sessions.first(where: { $0.id == sessionID }) {
                    Button {
                        store.resume(session: session)
                    } label: {
                        Label(AppStrings.localized("pomodoro.action.resume"), systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        store.completeActivePomodoro()
                    } label: {
                        Label(AppStrings.localized("pomodoro.action.completeRound"), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(role: .destructive) {
                    store.cancelActivePomodoro()
                } label: {
                    Label(AppStrings.cancel, systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else {
            Button {
                store.startPomodoroForSelectedTask()
            } label: {
                Label(AppStrings.localized("pomodoro.action.start"), systemImage: "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}

struct InspectorSummaryCard: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        if let task = store.selectedTask {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(AppStrings.localized("task.snapshot"), systemImage: "smallcircle.filled.circle")
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(store.activeSegments.contains { $0.taskID == task.id } ? AppStrings.running : task.status.displayName)
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
                    SmallStat(title: AppStrings.localized("task.field.today"), value: DurationFormatter.compact(store.secondsForTaskToday(task)))
                    Divider()
                    SmallStat(title: AppStrings.localized("task.field.week"), value: DurationFormatter.compact(store.secondsForTaskThisWeek(task)))
                }

                if let rollup = store.rollup(for: task.id) {
                    Divider()
                    HStack {
                        SmallStat(title: AppStrings.localized("forecast.remaining"), value: rollup.remainingSeconds.map(DurationFormatter.compact) ?? AppStrings.localized("forecast.noEstimate"))
                        Divider()
                        SmallStat(title: AppStrings.localized("forecast.projectedDays"), value: rollup.projectedDays.map { String(format: AppStrings.localized("forecast.daysFormat"), $0) } ?? AppStrings.localized("forecast.noEstimate"))
                    }
                }

                Text(task.notes ?? AppStrings.localized("task.notes.empty"))
                    .font(.subheadline)
                    .foregroundStyle(task.notes == nil ? .secondary : .primary)
                    .foregroundStyle(.secondary)
            }
            .appCard(padding: 18)
        }
    }
}
