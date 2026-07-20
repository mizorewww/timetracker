import Foundation

struct InboxSuggestionDestinationPresentation: Equatable {
    let kind: InboxSuggestionDestinationKind?
    let targetTitle: String
    let isAvailable: Bool

    var summary: String {
        localizedFormat(summaryKey, targetTitle)
    }

    var applyTitle: String {
        AppStrings.localized(applyTitleKey)
    }

    var automationIdentifier: String {
        kind?.rawValue ?? "invalid"
    }

    private var summaryKey: String {
        switch kind {
        case .childTask:
            "inbox.suggestion.destination.childTaskFormat"
        case .category:
            "inbox.suggestion.destination.categoryFormat"
        case .checklist:
            "inbox.suggestion.destination.checklistFormat"
        case nil:
            "inbox.suggestion.destination.invalidFormat"
        }
    }

    private var applyTitleKey: String {
        switch kind {
        case .childTask:
            "inbox.suggestion.apply.childTask"
        case .category:
            "inbox.suggestion.apply.category"
        case .checklist:
            "inbox.suggestion.apply.checklist"
        case nil:
            "inbox.suggestion.apply.unavailable"
        }
    }

    private func localizedFormat(_ key: String, _ argument: String) -> String {
        String.localizedStringWithFormat(
            AppStrings.localized(key),
            argument
        )
    }
}

extension TimeTrackerStore {
    func inboxSuggestionDestinationPresentation(
        for suggestion: InboxSuggestion
    ) -> InboxSuggestionDestinationPresentation {
        let fallbackTitle = AppStrings.localized(
            "inbox.suggestion.missingTarget"
        )
        guard let destination = suggestion.manualRouteDestination else {
            return InboxSuggestionDestinationPresentation(
                kind: nil,
                targetTitle: fallbackTitle,
                isAvailable: false
            )
        }

        switch destination {
        case let .childTask(parentTaskID):
            let target = task(for: parentTaskID)
            return InboxSuggestionDestinationPresentation(
                kind: .childTask,
                targetTitle: target?.title ?? fallbackTitle,
                isAvailable: target != nil &&
                    trackableTaskIDs.contains(parentTaskID)
            )
        case let .category(categoryID):
            let target = taskCategory(for: categoryID)
            return InboxSuggestionDestinationPresentation(
                kind: .category,
                targetTitle: target?.title ?? fallbackTitle,
                isAvailable: target != nil
            )
        case let .checklist(taskID):
            let target = task(for: taskID)
            return InboxSuggestionDestinationPresentation(
                kind: .checklist,
                targetTitle: target?.title ?? fallbackTitle,
                isAvailable: target != nil &&
                    trackableTaskIDs.contains(taskID)
            )
        }
    }
}
