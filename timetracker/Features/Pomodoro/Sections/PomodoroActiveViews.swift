import SwiftUI

struct ActivePomodoroCard: View {
    let store: TimeTrackerStore
    let run: PomodoroRun
    let requestCancel: () -> Void

    private var task: TaskNode? {
        store.task(for: run.taskID)
    }

    private var taskTitle: String {
        task?.title ?? store.taskTitle(for: run)
    }

    private var taskIdentity: String {
        task.map(store.path(for:)) ?? taskTitle
    }

    private var taskColor: Color {
        Color(hex: task?.colorHex) ?? PomodoroStyle.accent
    }

    var body: some View {
        PomodoroPageLayout {
            VStack(alignment: .leading, spacing: 24) {
                phaseHeader

                PomodoroActiveCountdownView(
                    store: store,
                    run: run,
                    taskTitle: taskTitle,
                    taskParentPath: task.flatMap(store.parentPath(for:)),
                    taskIdentity: taskIdentity,
                    taskColor: taskColor,
                    canResumeFocus: task.map(store.isTaskAvailableForTracking) == true
                )

                Divider()
                stopButton
            }
            .appNativeCard(padding: 24)
            .accessibilityIdentifier("pomodoro.active")
        } secondary: {
            PomodoroLedgerCard(store: store)
        }
        .sensoryFeedback(.success, trigger: run.completedFocusRounds)
    }

    private var phaseHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(store.pomodoroStateLabel(for: run), systemImage: phaseIcon)
                .font(.headline)
                .foregroundStyle(taskColor)

            Text(roundDescription)
                .font(roundDescriptionFont)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var roundDescriptionFont: Font {
        .body
    }

    private var stopButton: some View {
        Button(role: .destructive, action: requestCancel) {
            Label(AppStrings.localized("pomodoro.stop"), systemImage: "stop.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("pomodoro.stop")
    }

    private var roundDescription: String {
        if run.state == .shortBreak || run.state == .longBreak {
            return String(
                format: AppStrings.localized("pomodoro.roundsCompleted"),
                run.completedFocusRounds,
                run.targetRounds
            )
        }
        return String(
            format: AppStrings.localized("pomodoro.roundProgress"),
            min(run.completedFocusRounds + 1, run.targetRounds),
            run.targetRounds
        )
    }

    private var phaseIcon: String {
        switch run.state {
        case .shortBreak, .longBreak:
            "cup.and.saucer.fill"
        case .focusing, .interrupted:
            "flame.fill"
        case .planned:
            "timer"
        case .completed:
            "checkmark.circle.fill"
        case .cancelled:
            "xmark.circle.fill"
        }
    }
}
