import SwiftUI

struct ActivePomodoroCard: View {
    @ObservedObject var store: TimeTrackerStore
    let run: PomodoroRun

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ActivePomodoroContent(
                store: store,
                run: run,
                remaining: store.pomodoroRemainingSeconds(for: run, now: context.date),
                progress: store.pomodoroProgress(for: run, now: context.date)
            )
            .padding(22)
            .frame(maxWidth: .infinity)
            .appCard(padding: 0)
            .accessibilityIdentifier("pomodoro.active")
        }
    }
}

private struct ActivePomodoroContent: View {
    @ObservedObject var store: TimeTrackerStore
    let run: PomodoroRun
    let remaining: Int
    let progress: Double

    var body: some View {
        VStack(spacing: 20) {
            ActivePomodoroHeader(store: store, run: run)
            PomodoroProgressRing(remaining: remaining, progress: progress)
            ActivePomodoroControls(store: store, run: run, remaining: remaining)
        }
    }
}

private struct ActivePomodoroHeader: View {
    @ObservedObject var store: TimeTrackerStore
    let run: PomodoroRun

    var body: some View {
        VStack(spacing: 6) {
            Label(store.pomodoroStateLabel(for: run), systemImage: run.state == .focusing ? "flame.fill" : "timer")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(run.state == .focusing ? .blue : .orange)
            Text(store.taskTitle(for: run))
                .font(.title2.weight(.semibold))
            Text("\(run.completedFocusRounds) / \(run.targetRounds) \(AppStrings.localized("pomodoro.roundUnit"))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PomodoroProgressRing: View {
    let remaining: Int
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                Text(DurationFormatter.clock(remaining))
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(remaining == 0 ? AppStrings.localized("pomodoro.canCompleteRound") : AppStrings.localized("pomodoro.remaining"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 240, height: 240)
    }
}

private struct ActivePomodoroControls: View {
    @ObservedObject var store: TimeTrackerStore
    let run: PomodoroRun
    let remaining: Int

    var body: some View {
        HStack(spacing: 12) {
            primaryAction
            cancelButton
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var primaryAction: some View {
        Button {
            store.completeActivePomodoro()
        } label: {
            Label(primaryActionTitle, systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    private var primaryActionTitle: String {
        remaining == 0 ? AppStrings.localized("pomodoro.action.completeRound") : AppStrings.localized("pomodoro.finishEarly")
    }

    private var cancelButton: some View {
        Button(role: .destructive) {
            store.cancelActivePomodoro()
        } label: {
            Label(AppStrings.cancel, systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
