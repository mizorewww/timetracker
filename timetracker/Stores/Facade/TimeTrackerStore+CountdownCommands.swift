import Foundation
import SwiftData

extension TimeTrackerStore {
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
