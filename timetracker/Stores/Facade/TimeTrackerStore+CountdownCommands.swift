import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func addCountdownEvent() -> Bool {
        performStoreCommand(
            eventsForOutcome: { _ in [.countdownChanged] }
        ) { session in
            try StoreScopedCountdownCommandCoordinator(
                session: session
            ).add()
        } != nil
    }

    @discardableResult
    func updateCountdownEvent(_ event: CountdownEvent, title: String? = nil, date: Date? = nil) -> Bool {
        performStoreCommand(
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
        } != nil
    }

    @discardableResult
    func deleteCountdownEvent(_ event: CountdownEvent) -> Bool {
        performStoreCommand(
            eventsForOutcome: { _ in [.countdownChanged] },
            onError: handleStoreScopedCountdownError
        ) { session in
            try StoreScopedCountdownCommandCoordinator(
                session: session
            ).delete(eventID: event.id)
        } != nil
    }

    private func handleStoreScopedCountdownError(_ error: Error) {
        if error is StoreScopedCountdownMutationError {
            refreshStoreScopedCountdownReadModels()
        }
        errorMessage = error.localizedDescription
    }

    private func refreshStoreScopedCountdownReadModels() {
        do {
            try refresh(plan: StoreRefreshPlan(scopes: [.countdown]))
        } catch {
            errorMessage = savedRefreshFailedMessage(error)
        }
    }
}
