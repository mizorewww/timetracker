import SwiftUI

struct PomodoroLedgerCard: View {
    @ObservedObject var store: TimeTrackerStore

    private var recentRuns: [PomodoroRun] {
        Array(store.pomodoroRuns.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.app("pomodoro.recent"))
                .font(.headline)

            if recentRuns.isEmpty {
                EmptyStateRow(title: AppStrings.localized("pomodoro.empty"), icon: "timer")
            } else {
                PomodoroRecentRunsList(store: store, runs: recentRuns)
            }
        }
        .padding(18)
        .appCard(padding: 0)
    }
}

private struct PomodoroRecentRunsList: View {
    @ObservedObject var store: TimeTrackerStore
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
    @ObservedObject var store: TimeTrackerStore
    let run: PomodoroRun

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName(for: run.state))
                .foregroundStyle(color(for: run.state))
            VStack(alignment: .leading, spacing: 3) {
                Text(store.taskTitle(for: run))
                    .font(.subheadline.weight(.medium))
                Text("\(store.pomodoroStateLabel(for: run)) · \(run.completedFocusRounds)/\(run.targetRounds) \(AppStrings.localized("pomodoro.roundUnit"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DurationFormatter.compact(run.focusSecondsPlanned))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
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
