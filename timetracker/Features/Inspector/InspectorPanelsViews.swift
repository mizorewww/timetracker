import SwiftUI

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
