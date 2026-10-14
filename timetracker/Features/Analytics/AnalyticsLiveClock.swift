import SwiftUI

extension View {
    /// Advances `liveNow` at the plan's deadline while the scene is active,
    /// and immediately on scene activation or a system clock/day/zone change.
    func liveAnalyticsClock(
        _ liveNow: Binding<Date>,
        plan: AnalyticsRefreshPlan?,
        scenePhase: ScenePhase
    ) -> some View {
        task(id: plan) {
            guard let plan else { return }
            let delay = max(0, plan.deadline.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            liveNow.wrappedValue = Date()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            liveNow.wrappedValue = Date()
        }
        .onSystemClockChange {
            liveNow.wrappedValue = Date()
        }
    }
}
