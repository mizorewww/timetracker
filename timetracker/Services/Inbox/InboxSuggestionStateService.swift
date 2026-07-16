import Foundation

enum InboxSuggestionStateKind: Equatable {
    case unavailable
    case eligible
    case pending
    case ready
    case dismissed
    case stale
}

struct InboxSuggestionStateService {
    func state(
        for readModel: InboxItemReadModel,
        suggestion: InboxSuggestion?,
        isInFlight: Bool
    ) -> InboxSuggestionStateKind {
        state(
            for: readModel.item,
            suggestion: suggestion,
            isInFlight: isInFlight,
            isCurrentSuggestionRevisionDismissed: readModel.isCurrentSuggestionRevisionDismissed
        )
    }

    func state(
        for item: InboxItem,
        suggestion: InboxSuggestion?,
        isInFlight: Bool
    ) -> InboxSuggestionStateKind {
        state(
            for: item,
            suggestion: suggestion,
            isInFlight: isInFlight,
            isCurrentSuggestionRevisionDismissed: item.isCurrentSuggestionRevisionDismissed
        )
    }

    private func state(
        for item: InboxItem,
        suggestion: InboxSuggestion?,
        isInFlight: Bool,
        isCurrentSuggestionRevisionDismissed: Bool
    ) -> InboxSuggestionStateKind {
        guard item.deletedAt == nil,
              item.isCompleted == false,
              normalizedTitle(item.title).isEmpty == false else {
            return .unavailable
        }

        if isInFlight {
            return .pending
        }

        if isCurrentSuggestionRevisionDismissed {
            return .dismissed
        }

        guard let suggestion, suggestion.deletedAt == nil else {
            // Compatibility for rows created before explicit revision identities existed.
            return item.suggestionGeneratedAt == nil ? .eligible : .dismissed
        }

        return suggestionMatchesItem(suggestion, item: item) ? .ready : .stale
    }

    func displaySuggestion(
        for item: InboxItem,
        suggestion: InboxSuggestion?
    ) -> InboxSuggestion? {
        state(for: item, suggestion: suggestion, isInFlight: false) == .ready ? suggestion : nil
    }

    func displaySuggestion(
        for readModel: InboxItemReadModel,
        suggestion: InboxSuggestion?
    ) -> InboxSuggestion? {
        state(for: readModel, suggestion: suggestion, isInFlight: false) == .ready ? suggestion : nil
    }

    func shouldAutoSuggest(
        item: InboxItem,
        suggestion: InboxSuggestion?,
        isInFlight: Bool
    ) -> Bool {
        switch state(for: item, suggestion: suggestion, isInFlight: isInFlight) {
        case .eligible, .stale:
            return true
        case .unavailable, .pending, .ready, .dismissed:
            return false
        }
    }

    func shouldAutoSuggest(
        readModel: InboxItemReadModel,
        suggestion: InboxSuggestion?,
        isInFlight: Bool
    ) -> Bool {
        switch state(for: readModel, suggestion: suggestion, isInFlight: isInFlight) {
        case .eligible, .stale:
            return true
        case .unavailable, .pending, .ready, .dismissed:
            return false
        }
    }

    func canStoreGeneratedSuggestion(
        item: InboxItem,
        requestedTitle: String,
        requestedIdentity: InboxSuggestionIdentity,
        currentSuggestion: InboxSuggestion?
    ) -> Bool {
        guard item.suggestionIdentity == requestedIdentity,
              normalizedTitle(item.title) == normalizedTitle(requestedTitle) else {
            return false
        }

        switch state(for: item, suggestion: currentSuggestion, isInFlight: false) {
        case .eligible, .stale:
            return true
        case .unavailable, .pending, .ready, .dismissed:
            return false
        }
    }

    func canStoreGeneratedSuggestion(
        readModel: InboxItemReadModel,
        requestedTitle: String,
        requestedIdentity: InboxSuggestionIdentity,
        currentSuggestion: InboxSuggestion?
    ) -> Bool {
        let item = readModel.item
        guard item.suggestionIdentity == requestedIdentity,
              normalizedTitle(item.title) == normalizedTitle(requestedTitle) else {
            return false
        }

        switch state(for: readModel, suggestion: currentSuggestion, isInFlight: false) {
        case .eligible, .stale:
            return true
        case .unavailable, .pending, .ready, .dismissed:
            return false
        }
    }

    private func suggestionMatchesItem(_ suggestion: InboxSuggestion, item: InboxItem) -> Bool {
        suggestion.belongs(to: item) &&
            normalizedTitle(suggestion.titleSnapshot) == normalizedTitle(item.title)
    }

    private func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
