import SwiftUI

enum TaskManagementRecurrenceRole: Equatable {
    case template
    case generated(TaskRecurrenceOccurrenceSnapshot?)

    var title: String {
        title(relativeTo: Date())
    }

    func title(relativeTo now: Date) -> String {
        switch self {
        case .template:
            return AppStrings.localized("task.recurrence.row.template")
        case .generated(nil):
            return AppStrings.localized("task.recurrence.row.generated")
        case let .generated(.some(occurrence)):
            guard let timeZone = TimeZone(
                identifier: occurrence.timeZoneIdentifier
            ) else {
                return AppStrings.localized("task.recurrence.row.generated")
            }
            if occurrence.dayKey == TaskRecurrenceDayKey.value(
                for: now,
                timeZone: timeZone
            ) {
                return AppStrings.localized("task.recurrence.row.today")
            }
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "task.recurrence.row.generatedDateFormat"
                ),
                occurrence.formattedDateText()
            )
        }
    }

    var identifierComponent: String {
        switch self {
        case .template: "template"
        case .generated: "generated"
        }
    }

    var systemImage: String {
        switch self {
        case .template: "calendar.badge.clock"
        case .generated: "calendar.badge.checkmark"
        }
    }

    @MainActor
    static func index(
        rules: [TaskRecurrenceRule],
        occurrences: [TaskRecurrenceOccurrence],
        incompleteTemplateTaskIDs: Set<UUID>,
        incompleteGeneratedTaskIDs: Set<UUID>
    ) -> [UUID: Self] {
        var result = incompleteGeneratedTaskIDs.reduce(
            into: [UUID: Self]()
        ) { $0[$1] = .generated(nil) }
        for taskID in incompleteTemplateTaskIDs {
            result[taskID] = .template
        }
        for rule in rules.visibleDeduplicatedByID() {
            result[rule.templateTaskID] = .template
        }
        var occurrencesByGeneratedTaskID: [
            UUID: [TaskRecurrenceOccurrence]
        ] = [:]
        for occurrence in occurrences.visibleDeduplicatedByID() {
            result[occurrence.templateTaskID] = .template
            occurrencesByGeneratedTaskID[
                occurrence.generatedTaskID,
                default: []
            ].append(occurrence)
        }
        for (taskID, rows) in occurrencesByGeneratedTaskID
            where result[taskID] == nil {
            let snapshot = rows.count == 1
                ? TaskRecurrenceOccurrenceSnapshot(occurrence: rows[0])
                : nil
            result[taskID] = .generated(snapshot)
        }
        return result
    }
}

struct TaskManagementRowSupplement {
    let recurrenceRole: TaskManagementRecurrenceRole?
    let quantityProgress: TaskQuantityProgressSnapshot?
}

struct TaskManagementRowSupplementProjection {
    private let recurrenceRolesByTaskID: [
        UUID: TaskManagementRecurrenceRole
    ]
    private let quantityProgressByTaskID: [
        UUID: TaskQuantityProgressSnapshot
    ]

    @MainActor
    init(store: TimeTrackerStore) {
        recurrenceRolesByTaskID = TaskManagementRecurrenceRole.index(
            rules: store.taskRecurrenceRules,
            occurrences: store.taskRecurrenceOccurrences,
            incompleteTemplateTaskIDs:
                store.incompleteRecurrenceTemplateTaskIDs,
            incompleteGeneratedTaskIDs:
                store.incompleteRecurrenceGeneratedTaskIDs
        )
        quantityProgressByTaskID =
            store.visibleTaskQuantityProgressByTaskID()
    }

    func supplement(for taskID: UUID) -> TaskManagementRowSupplement {
        TaskManagementRowSupplement(
            recurrenceRole: recurrenceRolesByTaskID[taskID],
            quantityProgress: quantityProgressByTaskID[taskID]
        )
    }
}

struct TaskManagementRowPresentation {
    let identity: TaskIdentityPresentation
    let identityContext: TaskIdentityPresentation.Context
    let progress: ChecklistProgress
    let rollup: TaskRollup?
    let workedSeconds: Int
    let childCount: Int
    let isRunning: Bool
    var recurrenceRole: TaskManagementRecurrenceRole? = nil
    var quantityProgress: TaskQuantityProgressSnapshot? = nil

    var quantityProgressText: String? {
        guard let quantityProgress else { return nil }
        return String.localizedStringWithFormat(
            AppStrings.localized("task.quantity.row.progressFormat"),
            Int64(quantityProgress.totalAmount),
            Int64(quantityProgress.targetAmount),
            quantityProgress.unitLabel
        )
    }
}

struct TaskManagementRowContent: View {
    let presentation: TaskManagementRowPresentation
    let showsNavigationChevron: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TaskSummaryRow(
                presentation: presentation.identity,
                context: presentation.identityContext,
                iconSize: 30,
                metadata: TaskSummaryRowMetadata(
                    checklistProgress:
                        presentation.progress.totalCount > 0
                        ? presentation.progress
                        : nil,
                    workedSeconds: presentation.workedSeconds,
                    isRunning: presentation.isRunning,
                    showsNavigationChevron: showsNavigationChevron
                )
            )
            TaskManagementProgressContextLine(
                presentation: presentation
            )
            .padding(.leading, 42)
        }
        .padding(.vertical, 6)
    }
}

private struct TaskManagementProgressContextLine: View {
    let presentation: TaskManagementRowPresentation

    @ViewBuilder
    var body: some View {
        if presentation.recurrenceRole != nil ||
            presentation.quantityProgressText != nil {
            HStack(spacing: 10) {
                if let role = presentation.recurrenceRole {
                    Label(role.title, systemImage: role.systemImage)
                        .accessibilityIdentifier(
                            "tasks.row.recurrence.\(role.identifierComponent).\(presentation.identity.id.uuidString)"
                        )
                }
                if let quantity = presentation.quantityProgressText {
                    Text(quantity)
                        .monospacedDigit()
                        .accessibilityIdentifier(
                            "tasks.row.quantity.\(presentation.identity.id.uuidString)"
                        )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}
