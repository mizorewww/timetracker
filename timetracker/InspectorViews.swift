import SwiftUI

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
                    if !store.children(of: task).isEmpty {
                        TaskForecastPanel(store: store, task: task)
                    }
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
                InfoRow(
                    title: AppStrings.localized("task.field.total"),
                    value: DurationFormatter.compact(store.rollup(for: task.id)?.workedSeconds ?? store.secondsForTaskTotalRollup(task))
                )
                InfoRow(title: AppStrings.localized("task.field.today"), value: DurationFormatter.compact(store.secondsForTaskTodayRollup(task)))
                InfoRow(title: AppStrings.localized("task.field.week"), value: DurationFormatter.compact(store.secondsForTaskThisWeekRollup(task)))
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
                    SmallStat(
                        title: AppStrings.localized("task.field.total"),
                        value: DurationFormatter.compact(store.rollup(for: task.id)?.workedSeconds ?? store.secondsForTaskTotalRollup(task))
                    )
                    Divider()
                    SmallStat(title: AppStrings.localized("task.field.today"), value: DurationFormatter.compact(store.secondsForTaskTodayRollup(task)))
                }

                if !store.children(of: task).isEmpty,
                   let rollup = store.rollup(for: task.id),
                   rollup.isDisplayableForecast {
                    Divider()
                    HStack {
                        SmallStat(title: AppStrings.localized("forecast.remaining"), value: rollup.remainingSeconds.map(DurationFormatter.compact) ?? AppStrings.localized("forecast.noEstimate"))
                        Divider()
                        SmallStat(title: AppStrings.localized("forecast.projectedDays"), value: rollup.projectedDaysDisplayText)
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
