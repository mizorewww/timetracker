import Foundation
import SwiftData

extension TimeTrackerStore {
    func toggleChecklistItem(_ item: ChecklistItem) throws {
        try performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedChecklistError
        ) { session in
            try StoreScopedChecklistCommandCoordinator(
                session: session
            ).setCompletion(
                taskID: item.taskID,
                itemID: item.id,
                isCompleted: !item.isCompleted
            )
        }
    }

    func addChecklistItem(taskID: UUID, title: String) throws {
        try performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: handleStoreScopedChecklistError
        ) { session in
            try StoreScopedChecklistCommandCoordinator(
                session: session
            ).add(taskID: taskID, title: title)
        }
    }

    private func handleStoreScopedChecklistError(_ error: Error) {
        if error is StoreScopedChecklistMutationError {
            refreshLoggingFailure(plan: StoreRefreshPlan(scopes: [.tasks, .checklist]))
        }
    }

    func checklistItems(for taskID: UUID) -> [ChecklistItem] {
        checklistDomainStore.items(for: taskID)
    }

    func checklistVisual(for item: ChecklistItem) -> ChecklistItemVisual? {
        checklistDomainStore.visual(for: item.id)
    }

    func checklistProgress(for taskID: UUID) -> ChecklistProgress {
        if let cached = rollupDomainStore.rollup(for: taskID)?.checklistProgress {
            return cached
        }
        let items = checklistItems(for: taskID)
        return ChecklistProgress(
            taskID: taskID,
            totalCount: items.count,
            completedCount: items.lazy.filter(\.isCompleted).count
        )
    }

    func rollup(for taskID: UUID) -> TaskRollup? {
        rollupDomainStore.rollup(for: taskID)
    }

    func forecastDisplayItems(limit: Int? = nil) -> [ForecastDisplayItem] {
        ForecastDisplayService.displayItems(tasks: tasks, rollups: rollupDomainStore.taskRollups, limit: limit)
    }

    func forecastDisplayItem(for taskID: UUID) -> ForecastDisplayItem? {
        ForecastDisplayService.displayItem(for: taskID, tasks: tasks, rollups: rollupDomainStore.taskRollups)
    }

    func addCountdownEvent() throws {
        try performStoreCommand(
            eventsForOutcome: { _ in [.countdownChanged] }
        ) { session in
            try StoreScopedCountdownCommandCoordinator(
                session: session
            ).add()
        }
    }

    func updateCountdownEvent(_ event: CountdownEvent, title: String? = nil, date: Date? = nil) throws {
        try performStoreCommand(
            eventsForOutcome: { _ in [.countdownChanged] },
            onError: handleStoreScopedCountdownError
        ) { session in
            try StoreScopedCountdownCommandCoordinator(
                session: session
            ).update(
                eventID: event.id,
                title: title,
                date: date
            )
        }
    }

    func deleteCountdownEvent(_ event: CountdownEvent) throws {
        try performStoreCommand(
            eventsForOutcome: { _ in [.countdownChanged] },
            onError: handleStoreScopedCountdownError
        ) { session in
            try StoreScopedCountdownCommandCoordinator(
                session: session
            ).delete(eventID: event.id)
        }
    }

    private func handleStoreScopedCountdownError(_ error: Error) {
        if error is StoreScopedCountdownMutationError {
            refreshLoggingFailure(plan: StoreRefreshPlan(scopes: [.countdown]))
        }
    }
}
