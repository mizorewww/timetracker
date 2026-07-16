import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func addCountdownEvent() -> Bool {
        perform(event: .countdownChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try countdownCommandHandler.add(context: modelContext)
        }
    }

    @discardableResult
    func updateCountdownEvent(_ event: CountdownEvent, title: String? = nil, date: Date? = nil) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            try StoreScopedCountdownCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).update(
                baseline: CountdownMutationBaseline(event: event),
                title: title,
                date: date
            )
            finishStoreScopedMutation(events: [.countdownChanged])
            return true
        } catch {
            if error is StoreScopedCountdownMutationError {
                refreshStoreScopedCountdownReadModels()
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func deleteCountdownEvent(_ event: CountdownEvent) -> Bool {
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            try StoreScopedCountdownCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).delete(baseline: CountdownMutationBaseline(event: event))
            finishStoreScopedMutation(events: [.countdownChanged])
            return true
        } catch {
            if error is StoreScopedCountdownMutationError {
                refreshStoreScopedCountdownReadModels()
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func refreshStoreScopedCountdownReadModels() {
        do {
            try refresh(plan: StoreRefreshPlan(scopes: [.countdown]))
        } catch {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                error.localizedDescription
            )
        }
    }
}
