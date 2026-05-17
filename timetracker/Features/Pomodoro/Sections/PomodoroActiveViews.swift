import SwiftUI

struct ActivePomodoroCard: View {
    @ObservedObject var store: TimeTrackerStore
    let run: PomodoroRun
    let requestCancel: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ActivePomodoroContent(
                store: store,
                run: run,
                remaining: store.pomodoroRemainingSeconds(for: run, now: context.date),
                requestCancel: requestCancel
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ActivePomodoroContent: View {
    @ObservedObject var store: TimeTrackerStore
    let run: PomodoroRun
    let remaining: Int
    let requestCancel: () -> Void
    @State private var isHolding = false
    @State private var isCompletingStop = false
    @State private var holdProgress = 0.0
    @State private var holdCompletionTask: Task<Void, Never>?
    @State private var displayedRemainingOverride: Int?

    private let holdDuration: TimeInterval = 0.9
    private let resetBeforeReturnDelay: TimeInterval = 0.08

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 286)

            PomodoroTimerFace(
                timeText: DurationFormatter.clock(displayedRemaining),
                title: store.taskTitle(for: run),
                titleColor: taskColor
            )
            .pomodoroTimerFaceSource(.active)
            .opacity(0)

            Spacer(minLength: 214)

            PomodoroStopControl(progress: holdProgress, showsProgress: isHolding)

            Spacer(minLength: 120)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(stopGesture)
        .onDisappear {
            holdCompletionTask?.cancel()
        }
    }

    private var accent: Color {
        PomodoroStyle.accent
    }

    private var taskColor: Color {
        Color(hex: store.task(for: run.taskID)?.colorHex) ?? accent
    }

    private var displayedRemaining: Int {
        displayedRemainingOverride ?? remaining
    }

    private var stopGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                startHoldIfNeeded()
            }
            .onEnded { _ in
                cancelHold()
            }
    }

    private func startHoldIfNeeded() {
        guard !isHolding && !isCompletingStop else { return }
        holdCompletionTask?.cancel()
        isCompletingStop = false
        displayedRemainingOverride = nil
        holdProgress = 0
        let plannedSeconds = run.focusSecondsPlanned
        withAnimation(.easeOut(duration: 0.12)) {
            isHolding = true
        }
        withAnimation(.linear(duration: holdDuration)) {
            holdProgress = 1
        }
        holdCompletionTask = Task {
            try? await Task.sleep(for: .seconds(holdDuration))
            guard !Task.isCancelled else { return }
            let shouldReturnToSetup = await MainActor.run {
                guard isHolding else { return false }
                isCompletingStop = true
                var resetTransaction = Transaction(animation: nil)
                resetTransaction.disablesAnimations = true
                withTransaction(resetTransaction) {
                    displayedRemainingOverride = plannedSeconds
                }
                withAnimation(.easeOut(duration: 0.12)) {
                    isHolding = false
                    holdProgress = 0
                }
                return true
            }
            guard shouldReturnToSetup else { return }
            try? await Task.sleep(for: .seconds(resetBeforeReturnDelay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                requestCancel()
            }
        }
    }

    private func cancelHold() {
        guard !isCompletingStop else { return }
        holdCompletionTask?.cancel()
        holdCompletionTask = nil
        guard isHolding else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isHolding = false
            holdProgress = 0
        }
    }
}

private struct PomodoroStopControl: View {
    let progress: Double
    let showsProgress: Bool

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if showsProgress {
                    PomodoroLinearProgress(progress: progress)
                } else {
                    Color.clear
                }
            }
            .frame(width: 152, height: 30)

            Text(.app("pomodoro.holdToStopFocus"))
                .font(.system(size: showsProgress ? 24 : 20, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .scaleEffect(showsProgress ? 0.98 : 1)
        .animation(.easeInOut(duration: 0.16), value: showsProgress)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(AppStrings.localized("pomodoro.holdToStopFocus"))
        .accessibilityIdentifier("pomodoro.stopControl")
    }
}

private struct PomodoroLinearProgress: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let trackHeight: CGFloat = 6
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PomodoroStyle.progressTrack)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(PomodoroStyle.accent)
                    .frame(width: max(trackHeight, proxy.size.width * progress.clamped(to: 0...1)), height: trackHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
