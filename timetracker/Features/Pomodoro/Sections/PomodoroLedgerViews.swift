import SwiftUI

struct PomodoroLedgerCard: View {
    let store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppStrings.localized("pomodoro.recent"), systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .accessibilityIdentifier("pomodoro.recent")

            PomodoroLedgerContent(store: store)
        }
        .appNativeCard(padding: 18)
    }
}

struct PomodoroLedgerContent: View {
    let store: TimeTrackerStore

    private var recentRuns: [PomodoroRun] {
        Array(store.pomodoroRuns.prefix(5))
    }

    var body: some View {
        if recentRuns.isEmpty {
            EmptyStateRow(title: AppStrings.localized("pomodoro.empty"), icon: "timer")
        } else {
            PomodoroRecentRunsList(store: store, runs: recentRuns)
        }
    }
}

private struct PomodoroRecentRunsList: View {
    let store: TimeTrackerStore
    let runs: [PomodoroRun]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                PomodoroRunRow(store: store, run: run)

                if index < runs.count - 1 {
                    Divider()
                }
            }
        }
    }
}

private struct PomodoroRunRow: View {
    let store: TimeTrackerStore
    let run: PomodoroRun

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: run.state))
                .foregroundStyle(color(for: run.state))
            VStack(alignment: .leading, spacing: 3) {
                Text(taskIdentity)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(taskIdentity)
        .accessibilityValue(detail)
    }

    private var taskIdentity: String {
        guard let task = store.task(for: run.taskID) else {
            return store.taskTitle(for: run)
        }
        return store.path(for: task)
    }

    private var detail: String {
        "\(store.pomodoroStateLabel(for: run)) · \(run.completedFocusRounds)/\(run.targetRounds) \(AppStrings.localized("pomodoro.roundUnit"))"
    }

    private func iconName(for state: PomodoroState) -> String {
        switch state {
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .focusing: return "flame.fill"
        case .shortBreak, .longBreak: return "cup.and.saucer.fill"
        case .planned: return "timer"
        case .interrupted: return "exclamationmark.circle.fill"
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
