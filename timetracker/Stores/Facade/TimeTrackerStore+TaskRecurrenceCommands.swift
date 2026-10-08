import Foundation
import SwiftData

extension TimeTrackerStore {
    /// Materializes only each rule's current local day. It is intentionally
    /// called from safe app-lifecycle points, never from raw CloudKit import.
    @discardableResult
    func materializeCurrentDailyTaskRecurrences(
        now: Date = Date()
    ) -> Bool {
        performTaskRecurrenceMutation {
            try $0.materializeCurrentDay(now: now)
        }
    }

    func nextDailyTaskRecurrenceBoundary(
        after now: Date
    ) -> Date? {
        taskRecurrenceRules.compactMap { rule in
            guard rule.isEnabled,
                  rule.deletedAt == nil,
                  parentEligibleTaskIDs.contains(rule.templateTaskID),
                  let timeZone = TimeZone(
                      identifier: rule.timeZoneIdentifier
                  )
            else {
                return nil
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            calendar.timeZone = timeZone
            guard let deadline = calendar.dateInterval(
                of: .day,
                for: now
            )?.end,
                deadline > now
            else {
                return nil
            }
            return deadline
        }.min()
    }
}

private extension TimeTrackerStore {
    func performTaskRecurrenceMutation(
        _ operation: (
            StoreScopedTaskRecurrenceCommandCoordinator
        ) throws -> TaskRecurrenceMutationOutcome
    ) -> Bool {
        performStoreCommand(
            eventsForOutcome: { $0.events },
            onError: { error in
                if error is TaskRecurrenceMutationError {
                    do {
                        try self.refresh(
                            plan: StoreRefreshPlan(scopes: [.tasks])
                        )
                    } catch {
                        self.errorMessage = self.savedRefreshFailedMessage(error)
                        return
                    }
                }
                self.errorMessage = error.localizedDescription
            },
            command: { container in
                try operation(
                    StoreScopedTaskRecurrenceCommandCoordinator(
                        container: container,
                        writeAuthorization: writeAuthorization
                    )
                )
            }
        ) != nil
    }
}
