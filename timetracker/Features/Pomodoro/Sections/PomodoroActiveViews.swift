import SwiftUI

struct ActivePomodoroCard: View {
    let store: TimeTrackerStore
    let run: PomodoroRun
    let requestCancel: () -> Void

    var body: some View {
        timeline
            .sensoryFeedback(.success, trigger: run.completedFocusRounds)
    }

    private var timeline: TimelineView<PeriodicTimelineSchedule, ActivePomodoroContent> {
        TimelineView(.periodic(from: Date.now, by: 1)) { context in
            ActivePomodoroContent(
                store: store,
                run: run,
                now: context.date,
                requestCancel: requestCancel
            )
        }
    }
}

private struct ActivePomodoroContent: View {
    let store: TimeTrackerStore
    let run: PomodoroRun
    let now: Date
    let requestCancel: () -> Void

    private var remaining: Int {
        store.pomodoroRemainingSeconds(for: run, now: now)
    }

    private var taskColor: Color {
        Color(hex: store.task(for: run.taskID)?.colorHex) ?? PomodoroStyle.accent
    }

    private var isBreakReady: Bool {
        remaining == 0 && (run.state == .shortBreak || run.state == .longBreak)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)
                phaseSummary
                progress

                if isBreakReady {
                    startNextFocusButton
                }

                stopButton
                Spacer(minLength: 24)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .accessibilityIdentifier("pomodoro.active")
    }

    private var phaseSummary: some View {
        VStack(spacing: 8) {
            Text(store.pomodoroStateLabel(for: run))
                .font(.headline)
                .foregroundStyle(.secondary)

            PomodoroTimerFace(
                timeText: DurationFormatter.clock(remaining),
                title: store.taskTitle(for: run),
                titleColor: taskColor
            )

            Text(roundDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var progress: some View {
        ProgressView(value: store.pomodoroProgress(for: run, now: now))
            .tint(taskColor)
            .accessibilityLabel(store.pomodoroStateLabel(for: run))
            .accessibilityValue(DurationFormatter.clock(remaining))
    }

    private var startNextFocusButton: some View {
        Button {
            store.advanceActivePomodoroPhase()
        } label: {
            Label(AppStrings.localized("pomodoro.startNextFocus"), systemImage: "play.circle.fill")
                .frame(maxWidth: 260, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("pomodoro.startNextFocus")
    }

    private var stopButton: some View {
        Button(role: .destructive, action: requestCancel) {
            Label(AppStrings.localized("pomodoro.stop"), systemImage: "stop.fill")
                .frame(maxWidth: 260)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("pomodoro.stop")
    }

    private var roundDescription: String {
        String(
            format: AppStrings.localized("pomodoro.roundProgress"),
            min(run.completedFocusRounds + 1, run.targetRounds),
            run.targetRounds
        )
    }
}
