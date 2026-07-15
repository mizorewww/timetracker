import SwiftUI

struct PomodoroView: View {
    let store: TimeTrackerStore
    @State private var selectedPlanID: UUID?
    @State private var isStopConfirmationPresented = false
    @State private var stopConfirmationRunID: UUID?

    private var availablePlans: [PomodoroPlan] {
        let plans = store.preferences.pomodoroPlans.map { $0.normalized() }
        return plans.isEmpty ? PomodoroPlan.defaultPlans : plans
    }

    private var selectedPlan: PomodoroPlan {
        availablePlans.first { $0.id == selectedPlanID } ?? availablePlans[0]
    }

    var body: some View {
        Group {
            if let run = store.activePomodoroRun {
                ActivePomodoroCard(store: store, run: run) {
                    stopConfirmationRunID = run.id
                    isStopConfirmationPresented = true
                }
            } else {
                PomodoroSetupCard(
                    store: store,
                    plan: selectedPlan,
                    availablePlans: availablePlans,
                    selectedPlanID: $selectedPlanID
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
            store.reconcileActivePomodoro(now: Date())
        }
        .onChange(of: store.preferences.pomodoroPlans) { _, _ in
            normalizeSelectedPlan()
        }
        .onChange(of: store.activePomodoroRun?.id) { _, activeRunID in
            guard isStopConfirmationPresented,
                  activeRunID != stopConfirmationRunID else {
                return
            }
            isStopConfirmationPresented = false
            stopConfirmationRunID = nil
        }
        .onChange(of: isStopConfirmationPresented) { _, isPresented in
            if isPresented == false {
                stopConfirmationRunID = nil
            }
        }
        .confirmationDialog(
            AppStrings.localized("pomodoro.stop.confirm.title"),
            isPresented: $isStopConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(AppStrings.localized("pomodoro.stop"), role: .destructive) {
                guard store.activePomodoroRun?.id == stopConfirmationRunID else {
                    stopConfirmationRunID = nil
                    return
                }
                store.cancelActivePomodoro()
                stopConfirmationRunID = nil
            }
            Button(AppStrings.cancel, role: .cancel) {
                stopConfirmationRunID = nil
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
