import SwiftUI

struct PomodoroActiveCountdownView: View {
    let store: TimeTrackerStore
    let run: PomodoroRun
    let taskTitle: String
    let taskParentPath: String?
    let taskIdentity: String
    let taskColor: Color
    let canResumeFocus: Bool
    @Environment(\.pageLiveClocksActive) private var liveClocksActive
    @State private var lastLiveDate = Date()

    private var isBreak: Bool {
        run.state == .shortBreak || run.state == .longBreak
    }

    var body: some View {
        Group {
            if liveClocksActive {
                liveCountdown
            } else {
                // Fully stop the schedule while this page is not the selected
                // tab: the frozen value is re-rendered on reselection, and the
                // first live tick refreshes it within a second.
                countdown(at: lastLiveDate)
            }
        }
        .accessibilityIdentifier("pomodoro.countdown")
    }

    private var liveCountdown: some View {
        TimelineView(PomodoroCountdownSchedule(deadline: run.phaseDeadline)) { context in
            if context.date != lastLiveDate {
                lastLiveDate = context.date
            }
            return countdown(at: context.date)
        }
    }

    private func countdown(at date: Date) -> some View {
        let remaining = store.pomodoroRemainingSeconds(for: run, now: date)
        return VStack(spacing: 20) {
            PomodoroTimerFace(
                timeText: DurationFormatter.clock(remaining),
                timeValue: remaining,
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
                if canResumeFocus == false {
                    Label(
                        AppStrings.localized("pomodoro.resume.unavailable"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(unavailableMessageFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pomodoro.resumeUnavailable")
                }
                resumeButton(remaining: remaining)
            }
        }
    }

    private var unavailableMessageFont: Font {
        .callout
    }

    private func resumeButton(remaining: Int) -> some View {
        let presentation = PomodoroBreakActionPresentation(remainingSeconds: remaining)
        let phase = PomodoroPhaseToken(run: run)
        return Button {
            store.resumeActivePomodoroAfterBreak(phase: phase)
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
        .disabled(canResumeFocus == false)
        .accessibilityHint(
            AppStrings.localized(
                canResumeFocus ? presentation.hintKey : "pomodoro.resume.unavailable"
            )
        )
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
