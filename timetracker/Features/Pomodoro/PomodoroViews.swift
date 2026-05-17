import SwiftUI

struct PomodoroView: View {
    @ObservedObject var store: TimeTrackerStore
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var selectedPlanID: UUID?
    @State private var isReturningToSetup = false
    @State private var returningFocusSeconds: Int?
    @State private var pendingCancelTask: Task<Void, Never>?
    @State private var timerFaceFrames: [PomodoroTimerFaceSource: CGRect] = [:]

    private var availablePlans: [PomodoroPlan] {
        let plans = store.preferences.pomodoroPlans.map { $0.normalized() }
        return plans.isEmpty ? PomodoroPlan.defaultPlans : plans
    }

    private var selectedPlan: PomodoroPlan {
        availablePlans.first { $0.id == selectedPlanID } ?? availablePlans[0]
    }

    private var selectedTask: TaskNode? {
        store.selectedTaskID.flatMap { store.task(for: $0) }
    }

    private var selectedTaskColor: Color {
        Color(hex: selectedTask?.colorHex) ?? PomodoroStyle.accent
    }

    private var isCompactPhone: Bool {
        #if os(iOS)
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
        #else
        false
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            if isCompactPhone {
                PhoneLargePageHeader(destination: .pomodoro)
                    .padding(.horizontal, PhoneRootChromeMetrics.pageHorizontalPadding)
                    .padding(.top, 0)
            }
            #endif

            GeometryReader { proxy in
                ZStack {
                    VStack(spacing: 0) {
                        if let run = store.activePomodoroRun, !isReturningToSetup {
                            ActivePomodoroCard(
                                store: store,
                                run: run,
                                requestCancel: {
                                    returnToSetupThenCancel(run)
                                }
                            )
                        } else {
                            PomodoroSetupCard(
                                store: store,
                                plan: selectedPlan,
                                availablePlans: availablePlans,
                                selectedPlanID: $selectedPlanID,
                                displayedFocusSecondsOverride: returningFocusSeconds,
                                rendersTimerContent: !isReturningToSetup
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        PomodoroHighRefreshTimerFace(content: timerFaceContent(now: context.date), frame: timerFaceFrame)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(showsTimerOverlay ? 1 : 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .coordinateSpace(name: PomodoroStyle.timerCoordinateSpace)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(AppStrings.pomodoro)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .phoneRootChrome(destination: .pomodoro, enabled: isCompactPhone)
        #endif
        .background(PomodoroBackgroundColor().ignoresSafeArea())
        .onAppear {
            normalizeSelectedPlan()
        }
        .onChange(of: store.preferences.pomodoroPlans) { _, _ in
            normalizeSelectedPlan()
        }
        .onPreferenceChange(PomodoroTimerFaceFramePreferenceKey.self) { frames in
            timerFaceFrames.merge(frames, uniquingKeysWith: { _, new in new })
        }
        .onDisappear {
            completePendingCancelIfNeeded()
        }
    }

    private func timerFaceContent(now: Date = Date()) -> PomodoroTimerFaceContent {
        if let run = store.activePomodoroRun, !isReturningToSetup {
            return PomodoroTimerFaceContent(
                timeText: DurationFormatter.clock(store.pomodoroRemainingSeconds(for: run, now: now)),
                title: store.taskTitle(for: run),
                titleColor: Color(hex: store.task(for: run.taskID)?.colorHex) ?? PomodoroStyle.accent
            )
        }

        return PomodoroTimerFaceContent(
            timeText: DurationFormatter.clock(returningFocusSeconds ?? selectedPlan.focusSeconds),
            title: selectedTask?.title ?? AppStrings.localized("pomodoro.chooseTask"),
            titleColor: selectedTaskColor
        )
    }

    private var timerFaceFrame: CGRect? {
        timerFaceFrames[timerFaceSource] ?? timerFaceFrames[timerFaceSource.fallback]
    }

    private var timerFaceSource: PomodoroTimerFaceSource {
        if store.activePomodoroRun != nil && !isReturningToSetup {
            return .active
        }
        return .setup
    }

    private var showsTimerOverlay: Bool {
        store.activePomodoroRun != nil || isReturningToSetup
    }

    private func normalizeSelectedPlan() {
        guard !availablePlans.isEmpty else { return }
        if selectedPlanID == nil || !availablePlans.contains(where: { $0.id == selectedPlanID }) {
            selectedPlanID = availablePlans[0].id
        }
    }

    private func returnToSetupThenCancel(_ run: PomodoroRun) {
        guard !isReturningToSetup else { return }
        pendingCancelTask?.cancel()

        var resetTransaction = Transaction(animation: nil)
        resetTransaction.disablesAnimations = true
        withTransaction(resetTransaction) {
            returningFocusSeconds = run.focusSecondsPlanned
        }

        var swapTransaction = Transaction(animation: nil)
        swapTransaction.disablesAnimations = true
        withTransaction(swapTransaction) {
            isReturningToSetup = true
        }

        pendingCancelTask = Task {
            try? await Task.sleep(for: .seconds(PomodoroStyle.timerTransitionDuration))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                completePendingCancelIfNeeded()
            }
        }
    }

    private func completePendingCancelIfNeeded() {
        pendingCancelTask?.cancel()
        pendingCancelTask = nil
        guard isReturningToSetup else { return }

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            store.cancelActivePomodoro()
            isReturningToSetup = false
            returningFocusSeconds = nil
        }
    }
}

private struct PomodoroBackgroundColor: View {
    var body: some View {
        PomodoroStyle.background
    }
}

enum PomodoroStyle {
    static let background = AppColors.background
    static let timerText = Color.primary
    static let accent = Color(red: 0, green: 0.533, blue: 1)
    static let progressTrack = Color.primary.opacity(0.16)
    static let timerCoordinateSpace = "pomodoro.timerFace.coordinateSpace"
    static let timerTransitionDuration: TimeInterval = 0.62
    static let timerTransitionAnimation = Animation.timingCurve(0.2, 0.86, 0.22, 1, duration: timerTransitionDuration)
}

private extension PomodoroTimerFaceSource {
    var fallback: PomodoroTimerFaceSource {
        switch self {
        case .setup: return .active
        case .active: return .setup
        }
    }
}

enum PomodoroPreset: String, CaseIterable, Identifiable {
    case classic = "25 / 5"
    case deep = "50 / 10"
    case quick = "15 / 3"
    case custom = "custom"

    var id: String { rawValue }

    var focusSeconds: Int {
        focusMinutes * 60
    }

    var breakSeconds: Int {
        breakMinutes * 60
    }

    var focusMinutes: Int {
        switch self {
        case .classic: return 25
        case .deep: return 50
        case .quick: return 15
        case .custom: return 25
        }
    }

    var breakMinutes: Int {
        switch self {
        case .classic: return 5
        case .deep: return 10
        case .quick: return 3
        case .custom: return 5
        }
    }

    var title: String {
        switch self {
        case .classic: return AppStrings.localized("pomodoro.preset.classic")
        case .deep: return AppStrings.localized("pomodoro.preset.deep")
        case .quick: return AppStrings.localized("pomodoro.preset.quick")
        case .custom: return AppStrings.localized("pomodoro.custom")
        }
    }
}
