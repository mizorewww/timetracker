import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func createDailyTaskRecurrence(
        templateTaskID: UUID,
        startDayKey: String,
        timeZoneIdentifier: String,
        now: Date = Date()
    ) -> Bool {
        performTaskRecurrenceMutation {
            try $0.createDailyRule(
                templateTaskID: templateTaskID,
                startDayKey: startDayKey,
                timeZoneIdentifier: timeZoneIdentifier,
                now: now
            )
        }
    }

    @discardableResult
    func setTaskRecurrenceEnabled(
        baseline: TaskRecurrenceRuleMutationBaseline,
        isEnabled: Bool,
        now: Date = Date()
    ) -> Bool {
        performTaskRecurrenceMutation {
            try $0.setEnabled(
                baseline: baseline,
                isEnabled: isEnabled,
                now: now
            )
        }
    }

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
                  ) else {
                return nil
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US_POSIX")
            calendar.timeZone = timeZone
            guard let deadline = calendar.dateInterval(
                of: .day,
                for: now
            )?.end,
            deadline > now else {
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
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            let outcome = try operation(
                StoreScopedTaskRecurrenceCommandCoordinator(
                    container: modelContext.container,
                    writeAuthorization: writeAuthorization
                )
            )
            finishStoreScopedMutation(events: outcome.events)
            return true
        } catch {
            if error is TaskRecurrenceMutationError {
                do {
                    try refresh(
                        plan: StoreRefreshPlan(scopes: [.tasks])
                    )
                } catch {
                    errorMessage = String(
                        format: AppStrings.localized(
                            "error.savedRefreshFailed"
                        ),
                        error.localizedDescription
                    )
                    return false
                }
            }
            errorMessage = error.localizedDescription
            return false
        }
    }
}
