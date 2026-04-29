import Foundation
import SwiftData

extension TimeTrackerStore {
    func addCountdownEvent() {
        perform(event: .countdownChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try countdownCommandHandler.add(context: modelContext)
        }
    }

    func updateCountdownEvent(_ event: CountdownEvent, title: String? = nil, date: Date? = nil) {
        perform(event: .countdownChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try countdownCommandHandler.update(event, title: title, date: date, context: modelContext)
        }
    }

    func deleteCountdownEvent(_ event: CountdownEvent) {
        perform(event: .countdownChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try countdownCommandHandler.softDelete(event, context: modelContext)
        }
    }
}
