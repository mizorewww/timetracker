import Foundation
import SwiftData

/// Serializes recurrence rule changes and current-day materialization with the
/// same store lock used by task and timer commands. Scene-owned SwiftData
/// models never cross this boundary.
@MainActor
struct StoreScopedTaskRecurrenceCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String
    let didReachCheckpoint:
        (TaskRecurrenceMutationCheckpoint) throws -> Void

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String = DeviceIdentity.current,
        didReachCheckpoint: @escaping
        (TaskRecurrenceMutationCheckpoint) throws -> Void = { _ in }
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.didReachCheckpoint = didReachCheckpoint
    }

    func materializeCurrentDay(
        now: Date = Date()
    ) throws -> TaskRecurrenceMutationOutcome {
        try withFreshState { context, state in
            var outcome = TaskRecurrenceMutationOutcome.noChanges
            let rules = state.rulesByID.values.sorted {
                $0.id.uuidString < $1.id.uuidString
            }
            for rule in rules {
                guard rule.deletedAt == nil,
                      rule.isEnabled,
                      rule.id == TaskProgressIdentity.recurrenceRuleID(
                          templateTaskID: rule.templateTaskID
                      ),
                      rule.cadenceRaw ==
                      TaskRecurrenceCadence.daily.rawValue,
                      TaskRecurrenceDayKey.isCanonical(rule.startDayKey),
                      Self.validTimeZone(rule.timeZoneIdentifier) != nil,
                      state.templateEligibleTaskIDs.contains(
                          rule.templateTaskID
                      ),
                      let template = state.taskByID[rule.templateTaskID],
                      template.deletedAt == nil,
                      template.isArchivedForLifecycle == false
                else {
                    continue
                }
                try materializeCurrentDay(
                    rule: rule,
                    template: template,
                    now: now,
                    context: context,
                    state: state,
                    outcome: &outcome
                )
            }
            return outcome
        }
    }
}

extension StoreScopedTaskRecurrenceCommandCoordinator {
    func withFreshState<Result>(
        _ operation: (
            ModelContext,
            inout TaskRecurrencePersistenceState
        ) throws -> Result
    ) throws -> Result {
        try writeAuthorization.requireUserWritesAllowed()
        return try StoreScopedTimerMutationTransaction(
            scope: TimerStoreScope(container: container),
            container: container
        ).withFreshContext(author: .localMutation) { context in
            var state = try TaskRecurrencePersistenceState(context: context)
            return try operation(context, &state)
        }
    }

    static func validate(
        startDayKey: String,
        timeZoneIdentifier: String
    ) throws {
        guard TaskRecurrenceDayKey.isCanonical(startDayKey) else {
            throw TaskRecurrenceMutationError.invalidStartDay
        }
        guard validTimeZone(timeZoneIdentifier) != nil else {
            throw TaskRecurrenceMutationError.invalidTimeZone
        }
    }

    static func validTimeZone(_ identifier: String) -> TimeZone? {
        guard identifier.isEmpty == false,
              identifier.utf8.count <=
              TaskRecurrencePolicy.maximumTimeZoneIdentifierByteCount
        else {
            return nil
        }
        return TimeZone(identifier: identifier)
    }
}
