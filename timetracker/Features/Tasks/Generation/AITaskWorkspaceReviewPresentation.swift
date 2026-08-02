import Foundation

struct AITaskWorkspaceReviewPresentation: Equatable {
    let operations: [AITaskWorkspaceOperationPresentation]
    let counts: AITaskWorkspaceOperationCounts
    let mutationCount: Int
    let hasDestructiveOperations: Bool

    init(
        operations: [AITaskWorkspaceOperation],
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) {
        counts = AITaskWorkspaceOperationCounts(operations: operations)
        mutationCount = operations.filter(\.isMutation).count
        hasDestructiveOperations = operations.contains(where: \.isDestructive)
        var occurrences: [AITaskWorkspaceOperationPresentation.IdentitySeed: Int] = [:]
        self.operations = operations.enumerated().map { index, operation in
            let seed = operation.presentationIdentitySeed
            let occurrence = occurrences[seed, default: 0]
            occurrences[seed] = occurrence + 1
            return AITaskWorkspaceOperationPresentation(
                id: .init(seed: seed, occurrence: occurrence),
                accessibilityIndex: index,
                operation: operation,
                original: original,
                resulting: resulting
            )
        }
    }
}

struct AITaskWorkspaceOperationPresentation: Identifiable, Equatable {
    struct IdentitySeed: Hashable {
        let kind: Kind
        let entityID: UUID
    }

    struct ID: Hashable {
        let seed: IdentitySeed
        let occurrence: Int
    }

    enum Kind: Hashable {
        case reuseCategory
        case createCategory
        case updateCategory
        case deleteCategory
        case createTask
        case updateTask
        case archiveTask
        case createChecklistItem
        case updateChecklistItem
        case deleteChecklistItem
    }

    let id: ID
    let accessibilityIndex: Int
    let operation: AITaskWorkspaceOperation
    let title: String
    let context: String
    let fieldChanges: [AITaskWorkspaceFieldChange]

    var accessibilityLabel: String {
        var components = [operation.localizedKind, title]
        if context.isEmpty == false {
            components.append(context)
        }
        for change in fieldChanges {
            components.append(change.field.localizedTitle)
            components.append(
                "\(AppStrings.localized("aiTaskPlan.diff.before")): " +
                    change.before.localizedText
            )
            components.append(
                "\(AppStrings.localized("aiTaskPlan.diff.after")): " +
                    change.after.localizedText
            )
        }
        return components.joined(separator: ", ")
    }

    init(
        id: ID,
        accessibilityIndex: Int,
        operation: AITaskWorkspaceOperation,
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) {
        self.id = id
        self.accessibilityIndex = accessibilityIndex
        self.operation = operation
        title = operation.previewTitle(original: original, resulting: resulting)
        context = operation.previewContext(original: original, resulting: resulting)
        fieldChanges = operation.fieldChanges(original: original, resulting: resulting)
    }
}

enum AITaskWorkspacePreviewField: String, Hashable, Identifiable {
    case title
    case path
    case category
    case notes
    case estimatedTime
    case dueDate
    case icon
    case color
    case forecast
    case quantityGoal
    case recurrence
    case completion

    var id: Self {
        self
    }

    var localizedTitle: String {
        AppStrings.localized("aiTaskPlan.diff.field.\(rawValue)")
    }
}

struct AITaskWorkspaceFieldChange: Equatable, Identifiable {
    let field: AITaskWorkspacePreviewField
    let before: AITaskWorkspacePreviewValue
    let after: AITaskWorkspacePreviewValue

    var id: AITaskWorkspacePreviewField {
        field
    }
}

enum AITaskWorkspacePreviewValue: Equatable {
    case text(String)
    case optionalText(String?)
    case minutes(Int?)
    case date(Date?)
    case boolean(Bool)
    case icon(String)
    case color(String)
    case quantityGoal(TaskQuantityGoalDraft?)
    case recurrence(TaskDailyRecurrenceDraft?)

    var localizedText: String {
        switch self {
        case let .text(value):
            return value.isEmpty ? AppStrings.localized("common.none") : value
        case let .optionalText(value):
            return value ?? AppStrings.localized("common.none")
        case let .minutes(value):
            guard let value else { return AppStrings.localized("common.none") }
            return String.localizedStringWithFormat(
                AppStrings.localized("common.minutes"),
                value
            )
        case let .date(value):
            guard let value else { return AppStrings.localized("common.none") }
            return value.formatted(
                .dateTime.year().month(.abbreviated).day().hour().minute()
            )
        case let .boolean(value):
            return AppStrings.localized(
                value ? "aiTaskPlan.diff.value.yes" : "aiTaskPlan.diff.value.no"
            )
        case let .icon(value):
            return value
        case let .color(value):
            return TaskColorPalette.accessibilityName(for: value)
        case let .quantityGoal(value):
            guard let value else { return AppStrings.localized("common.none") }
            return String.localizedStringWithFormat(
                AppStrings.localized("aiTaskPlan.diff.value.quantityGoalFormat"),
                Int64(value.targetAmount),
                value.unitLabel
            )
        case let .recurrence(value):
            guard let value else { return AppStrings.localized("common.none") }
            return String.localizedStringWithFormat(
                AppStrings.localized("aiTaskPlan.diff.value.recurrenceFormat"),
                AppStrings.localized("task.recurrence.editor.everyDay"),
                AppStrings.localized(
                    value.isEnabled
                        ? "aiTaskPlan.diff.value.active"
                        : "aiTaskPlan.diff.value.paused"
                ),
                value.startDayKey,
                value.timeZoneIdentifier
            )
        }
    }
}
