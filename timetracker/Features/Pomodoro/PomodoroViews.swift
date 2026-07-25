import SwiftUI

struct PomodoroView: View {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var selectedPlanID: UUID?
    @State private var focusTaskID: UUID?
    @State private var isStopConfirmationPresented = false
    @State private var stopConfirmationPhase: PomodoroPhaseToken?

    private var availablePlans: [PomodoroPlan] {
        let plans = store.preferences.pomodoroPlans.map { $0.normalized() }
        return plans.isEmpty ? PomodoroPlan.defaultPlans : plans
    }

    private var selectedPlan: PomodoroPlan {
        availablePlans.first { $0.id == selectedPlanID } ?? availablePlans[0]
    }

    private var availableFocusTaskIDs: [UUID] {
        store.tasks
            .filter(store.isTaskAvailableForTracking)
            .map(\.id)
    }

    var body: some View {
        Group {
            if let run = store.activePomodoroRun {
                ActivePomodoroCard(store: store, run: run) {
                    stopConfirmationPhase = PomodoroPhaseToken(run: run)
                    isStopConfirmationPresented = true
                }
            } else {
                PomodoroSetupCard(
                    store: store,
                    plan: selectedPlan,
                    availablePlans: availablePlans,
                    selectedPlanID: $selectedPlanID,
                    focusTaskID: $focusTaskID,
                    selectFocusTask: presentFocusTaskPicker
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(AppStrings.focus)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .accessibilityIdentifier("pomodoro.view")
            .background(PomodoroBackgroundColor().ignoresSafeArea())
            .onAppear {
                normalizeSelectedPlan()
                normalizeFocusTaskSelection()
                store.reconcileActivePomodoro(now: Date())
            }
            .onChange(of: store.preferences.pomodoroPlans) { _, _ in
                normalizeSelectedPlan()
            }
            .onChange(of: availableFocusTaskIDs) { _, _ in
                normalizeFocusTaskSelection()
            }
            .onChange(of: store.activePomodoroRun?.clientMutationID) { _, mutationID in
                guard isStopConfirmationPresented,
                      mutationID != stopConfirmationPhase?.mutationID
                else {
                    return
                }
                isStopConfirmationPresented = false
                stopConfirmationPhase = nil
            }
            .onChange(of: isStopConfirmationPresented) { _, isPresented in
                if isPresented == false {
                    stopConfirmationPhase = nil
                }
            }
            .confirmationDialog(
                AppStrings.localized("pomodoro.stop.confirm.title"),
                isPresented: $isStopConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(AppStrings.localized("pomodoro.stop"), role: .destructive) {
                    guard let stopConfirmationPhase else {
                        return
                    }
                    store.cancelActivePomodoro(phase: stopConfirmationPhase)
                    self.stopConfirmationPhase = nil
                }
                Button(AppStrings.cancel, role: .cancel) {
                    stopConfirmationPhase = nil
                }
            } message: {
                Text(.app("pomodoro.stop.confirm.message"))
            }
    }

    private func normalizeSelectedPlan() {
        guard !availablePlans.isEmpty else { return }
        if selectedPlanID == nil || !availablePlans.contains(where: { $0.id == selectedPlanID }) {
            selectedPlanID = availablePlans[0].id
        }
    }

    private func normalizeFocusTaskSelection() {
        let availableTaskIDs = Set(availableFocusTaskIDs)
        guard focusTaskID.map(availableTaskIDs.contains) != true else { return }

        if let selectedTaskID = store.selectedTaskID,
           availableTaskIDs.contains(selectedTaskID)
        {
            focusTaskID = selectedTaskID
        } else {
            focusTaskID = availableFocusTaskIDs.first
        }
    }

    private func presentFocusTaskPicker() {
        presentationRouter.presentPomodoroTaskPicker(
            selectedTaskID: focusTaskID,
            selectTask: { taskID in
                focusTaskID = taskID
            }
        )
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
    static let accent = Color.accentColor
    static let progressTrack = Color.primary.opacity(0.16)
}
