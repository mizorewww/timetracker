import Foundation
import SwiftUI

extension View {
    func taskRecurrenceLifecycle(
        store: TimeTrackerStore,
        isConfigured: Bool
    ) -> some View {
        modifier(
            TaskRecurrenceLifecycleModifier(
                store: store,
                isConfigured: isConfigured
            )
        )
    }
}

private struct TaskRecurrenceLifecycleModifier: ViewModifier {
    private static let boundarySearchOffset: TimeInterval = 0.001

    @Environment(\.scenePhase) private var scenePhase
    @State private var clockRevision = UUID()

    let store: TimeTrackerStore
    let isConfigured: Bool

    func body(content: Content) -> some View {
        content
            .task(id: scheduleIdentity) {
                await runSchedule()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .NSCalendarDayChanged
                )
            ) { _ in
                clockRevision = UUID()
                materializeIfReady()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .NSSystemClockDidChange
                )
            ) { _ in
                clockRevision = UUID()
                materializeIfReady()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: .NSSystemTimeZoneDidChange
                )
            ) { _ in
                clockRevision = UUID()
            }
    }

    private var scheduleIdentity: TaskRecurrenceScheduleIdentity {
        TaskRecurrenceScheduleIdentity(
            isReady: isConfigured &&
                store.effectivePersistenceWriteSafety == .ready,
            isActive: scenePhase == .active,
            clockRevision: clockRevision,
            taskReadModelRevision: store.taskReadModelRevision,
            ruleMutationIDs: store.taskRecurrenceRules
                .filter(\.isEnabled)
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map(\.clientMutationID)
        )
    }

    private func materializeIfReady() {
        guard scheduleIdentity.isReady,
              scheduleIdentity.isActive
        else {
            return
        }
        store.materializeCurrentDailyTaskRecurrences()
    }

    private func runSchedule() async {
        guard scheduleIdentity.isReady,
              scheduleIdentity.isActive
        else {
            return
        }
        var planningDate = Date()
        while Task.isCancelled == false {
            guard let deadline = store.nextDailyTaskRecurrenceBoundary(
                after: planningDate
            ) else {
                return
            }
            do {
                try await Task.sleep(
                    for: .seconds(
                        max(0, deadline.timeIntervalSinceNow)
                    )
                )
            } catch {
                return
            }
            guard Task.isCancelled == false,
                  scenePhase == .active,
                  store.effectivePersistenceWriteSafety == .ready
            else {
                return
            }
            let observedAt = max(Date(), deadline)
            store.materializeCurrentDailyTaskRecurrences(now: observedAt)
            planningDate = observedAt.addingTimeInterval(Self.boundarySearchOffset)
        }
    }
}

private struct TaskRecurrenceScheduleIdentity: Hashable {
    let isReady: Bool
    let isActive: Bool
    let clockRevision: UUID
    let taskReadModelRevision: UInt64
    let ruleMutationIDs: [UUID]
}
