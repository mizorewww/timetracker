import Foundation
import SwiftData

/// Identifies the checklist and visual state an advisory AI request observed.
/// A result may apply only if this state remains current when it completes.
struct ChecklistVisualSuggestionBaseline: Equatable, Sendable {
    let itemID: UUID
    let taskID: UUID
    let itemMutationID: UUID
    let normalizedTitle: String
    let visualID: UUID?
    let visualMutationID: UUID?
    let visualUserEditedAt: Date?

    init(item: ChecklistItem, visual: ChecklistItemVisual?, normalizedTitle: String) {
        itemID = item.id
        taskID = item.taskID
        itemMutationID = item.clientMutationID
        self.normalizedTitle = normalizedTitle
        visualID = visual?.id
        visualMutationID = visual?.clientMutationID
        visualUserEditedAt = visual?.userEditedAt
    }
}

@MainActor
extension StoreScopedChecklistCommandCoordinator {
    func applyVisualSuggestion(
        baseline: ChecklistVisualSuggestionBaseline,
        result: LLMChecklistVisualSuggestionResult
    ) throws -> ChecklistMutationOutcome {
        try withCanonicalTask(taskID: baseline.taskID) { context, tasks in
            guard TaskTrackingAvailabilityService()
                .trackableTaskIDs(tasks: tasks)
                .contains(baseline.taskID),
                let item = try visibleItems(taskID: baseline.taskID, context: context)
                .first(where: { $0.id == baseline.itemID }),
                item.clientMutationID == baseline.itemMutationID,
                ChecklistVisualSuggestionPolicy().normalizedTitle(item.title) == baseline.normalizedTitle,
                item.isCompleted == false
            else {
                return (nil, false)
            }

            let visual = try canonicalVisual(for: item.id, context: context)
            guard visualMatches(baseline: baseline, current: visual),
                  ChecklistVisualSuggestionPolicy().shouldSuggest(item: item, visual: visual)
            else {
                return (nil, false)
            }

            try ChecklistCommandHandler().applyVisualSuggestion(
                item: item,
                result: result,
                existingVisual: visual,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
            return (item.id, true)
        }
    }

    private func canonicalVisual(
        for checklistItemID: UUID,
        context: ModelContext
    ) throws -> ChecklistItemVisual? {
        let itemID = checklistItemID
        return try context.fetch(
            FetchDescriptor<ChecklistItemVisual>(
                predicate: #Predicate { $0.checklistItemID == itemID }
            )
        )
        .logicalWinnersByChecklistItemID()[checklistItemID]
    }

    private func visualMatches(
        baseline: ChecklistVisualSuggestionBaseline,
        current: ChecklistItemVisual?
    ) -> Bool {
        guard baseline.visualID == current?.id,
              baseline.visualMutationID == current?.clientMutationID,
              baseline.visualUserEditedAt == current?.userEditedAt
        else {
            return false
        }
        return current?.deletedAt == nil || current == nil
    }
}
