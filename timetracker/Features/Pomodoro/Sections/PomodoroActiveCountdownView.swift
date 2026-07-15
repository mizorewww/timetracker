import SwiftUI

struct PomodoroActiveCountdownView: View {
    let store: TimeTrackerStore
    let run: PomodoroRun
    let taskTitle: String
    let taskParentPath: String?
    let taskIdentity: String
    let taskColor: Color

    private var isBreak: Bool {
        run.state == .shortBreak || run.state == .longBreak
    }

    var body: some View {
        TimelineView(PomodoroCountdownSchedule(deadline: run.phaseDeadline)) { context in
            countdown(at: context.date)
        }
        .accessibilityIdentifier("pomodoro.countdown")
    }

    private func countdown(at date: Date) -> some View {
        let remaining = store.pomodoroRemainingSeconds(for: run, now: date)
        return VStack(spacing: 20) {
            PomodoroTimerFace(
                timeText: DurationFormatter.clock(remaining),
                title: taskTitle,
                subtitle: taskParentPath,
                titleColor: taskColor,
                spokenLabel: String(
                    format: AppStrings.localized("pomodoro.phaseTask.accessibility"),
                    store.pomodoroStateLabel(for: run),
                    taskIdentity
                ),
                spokenValue: String(
                    format: AppStrings.localized("pomodoro.remaining.accessibility"),
                    DurationFormatter.spoken(remaining)
                )
            )

            ProgressView(value: store.pomodoroProgress(for: run, now: date))
                .tint(taskColor)
                .accessibilityHidden(true)

            if isBreak {
                resumeButton(remaining: remaining)
            }
        }
    }

    private func resumeButton(remaining: Int) -> some View {
        let presentation = PomodoroBreakActionPresentation(remainingSeconds: remaining)
        let runID = run.id
        let expectedState = run.state
        return Button {
            store.resumeActivePomodoroAfterBreak(
                runID: runID,
                expectedState: expectedState
            )
        } label: {
            Label(
                AppStrings.localized(presentation.titleKey),
                systemImage: presentation.systemImage
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(taskColor)
        .frame(maxWidth: 320)
        .accessibilityHint(AppStrings.localized(presentation.hintKey))
        .accessibilityIdentifier("pomodoro.startNextFocus")
    }
}

struct PomodoroBreakActionPresentation: Equatable {
    let titleKey: String
    let hintKey: String
    let systemImage: String

    init(remainingSeconds: Int) {
        if remainingSeconds > 0 {
            titleKey = "pomodoro.skipBreak"
            hintKey = "pomodoro.skipBreak.hint"
            systemImage = "forward.fill"
        } else {
            titleKey = "pomodoro.startNextFocus"
            hintKey = "pomodoro.startNextFocus.hint"
            systemImage = "play.circle.fill"
        }
    }
}
