import Foundation

enum TaskProgressDraftMutationError: LocalizedError, Equatable {
    case invalidTargetAmount
    case unitRequired
    case unitContainsControlCharacter
    case unitByteLimitExceeded(actual: Int, maximum: Int)
    case unitChangeRequiresProgressReset
    case quantityGoalRemovalRequiresConfirmation
    case incompleteQuantityGraph
    case existingRecurrenceMustBePreserved

    var errorDescription: String? {
        switch self {
        case .invalidTargetAmount:
            AppStrings.localized("task.quantity.error.invalidTarget")
        case .unitRequired:
            AppStrings.localized("task.quantity.error.unitRequired")
        case .unitContainsControlCharacter:
            AppStrings.localized("task.quantity.error.unitControlCharacter")
        case let .unitByteLimitExceeded(actual, maximum):
            String.localizedStringWithFormat(
                AppStrings.localized("task.quantity.error.unitTooLong"),
                Int64(actual),
                Int64(maximum)
            )
        case .unitChangeRequiresProgressReset:
            AppStrings.localized("task.quantity.error.unitChangeRequiresReset")
        case .quantityGoalRemovalRequiresConfirmation:
            AppStrings.localized(
                "task.quantity.error.removalRequiresConfirmation"
            )
        case .incompleteQuantityGraph:
            AppStrings.localized("task.quantity.error.incompleteGraph")
        case .existingRecurrenceMustBePreserved:
            AppStrings.localized(
                "task.recurrence.error.existingRuleMustBePreserved"
            )
        }
    }
}

struct PreparedTaskQuantityGoalDraft: Equatable {
    let targetAmount: Int
    let unitLabel: String
}

struct PreparedTaskProgressDraft: Equatable {
    let quantityGoal: PreparedTaskQuantityGoalDraft?
    let confirmsQuantityProgressReset: Bool
    let dailyRecurrence: TaskDailyRecurrenceDraft?
}

enum TaskProgressDraftPersistencePolicy {
    static func prepare(
        quantityGoal: TaskQuantityGoalDraft?,
        dailyRecurrence: TaskDailyRecurrenceDraft?,
        confirmsQuantityProgressReset: Bool = false
    ) throws -> PreparedTaskProgressDraft {
        let preparedGoal: PreparedTaskQuantityGoalDraft?
        if let quantityGoal {
            preparedGoal = try prepareQuantityGoal(quantityGoal)
        } else {
            preparedGoal = nil
        }
        if let dailyRecurrence {
            try StoreScopedTaskRecurrenceCommandCoordinator.validate(
                startDayKey: dailyRecurrence.startDayKey,
                timeZoneIdentifier: dailyRecurrence.timeZoneIdentifier
            )
        }
        return PreparedTaskProgressDraft(
            quantityGoal: preparedGoal,
            confirmsQuantityProgressReset:
                confirmsQuantityProgressReset,
            dailyRecurrence: dailyRecurrence
        )
    }

    static func quantityValidationError(
        for draft: TaskQuantityGoalDraft?
    ) -> TaskProgressDraftMutationError? {
        do {
            if let draft {
                _ = try prepareQuantityGoal(draft)
            }
            return nil
        } catch let error as TaskProgressDraftMutationError {
            return error
        } catch {
            assertionFailure(
                "Quantity validation threw an unexpected error: \(error)"
            )
            return nil
        }
    }

    private static func prepareQuantityGoal(
        _ draft: TaskQuantityGoalDraft
    ) throws -> PreparedTaskQuantityGoalDraft {
        guard TaskQuantityPolicy.valueRange.contains(
            draft.targetAmount
        ) else {
            throw TaskProgressDraftMutationError.invalidTargetAmount
        }
        let unit = draft.unitLabel.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard unit.isEmpty == false else {
            throw TaskProgressDraftMutationError.unitRequired
        }
        guard unit.unicodeScalars.contains(
            where: CharacterSet.controlCharacters.contains
        ) == false else {
            throw TaskProgressDraftMutationError
                .unitContainsControlCharacter
        }
        let byteCount = unit.utf8.count
        guard byteCount <= TaskQuantityPolicy.maximumUnitLabelByteCount else {
            throw TaskProgressDraftMutationError.unitByteLimitExceeded(
                actual: byteCount,
                maximum: TaskQuantityPolicy.maximumUnitLabelByteCount
            )
        }
        return PreparedTaskQuantityGoalDraft(
            targetAmount: draft.targetAmount,
            unitLabel: unit
        )
    }
}
