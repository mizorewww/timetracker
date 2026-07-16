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
        perform(event: .countdownChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try countdownCommandHandler.update(event, title: title, date: date, context: modelContext)
        }
    }

    @discardableResult
    func deleteCountdownEvent(_ event: CountdownEvent) -> Bool {
        perform(event: .countdownChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try countdownCommandHandler.softDelete(event, context: modelContext)
        }
    }
}
