import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func addCountdownEvent() -> Bool {
        performStoreCommand(
            eventsForOutcome: { _ in [.countdownChanged] }
        ) { container in
            try StoreScopedCountdownCommandCoordinator(
                container: container,
                writeAuthorization: writeAuthorization
            ).add()
        } != nil
    }

    @discardableResult
    func updateCountdownEvent(_ event: CountdownEvent, title: String? = nil, date: Date? = nil) -> Bool {
        performStoreCommand(
            eventsForOutcome: { _ in [.countdownChanged] },
            onError: handleStoreScopedCountdownError
        ) { container in
            try StoreScopedCountdownCommandCoordinator(
                container: container,
                writeAuthorization: writeAuthorization
            ).update(
                baseline: CountdownMutationBaseline(event: event),
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
        ) { container in
            try StoreScopedCountdownCommandCoordinator(
                container: container,
                writeAuthorization: writeAuthorization
            ).delete(baseline: CountdownMutationBaseline(event: event))
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
