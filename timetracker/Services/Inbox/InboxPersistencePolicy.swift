import Foundation

struct PreparedInboxItemText {
    let title: String
    let notes: String?
    let suggestionReason: String?

    @MainActor
    func apply(to item: InboxItem) {
        item.title = title
        item.notes = notes
        item.suggestionReason = suggestionReason
    }
}

struct PreparedInboxSuggestionText {
    let reason: String?
    let iconName: String
    let colorHex: String
    let modelID: String?
    let titleSnapshot: String

    @MainActor
    func apply(to suggestion: InboxSuggestion) {
        suggestion.reason = reason
        suggestion.iconName = iconName
        suggestion.colorHex = colorHex
        suggestion.modelID = modelID
        suggestion.titleSnapshot = titleSnapshot
    }
}

@MainActor
struct PreparedInboxSuggestionMutation {
    let suggestion: InboxSuggestion
    let text: PreparedInboxSuggestionText
}

enum InboxPersistencePolicy {
    static func prepareItem(
        title: String,
        notes: String?,
        suggestionReason: String?
    ) throws -> PreparedInboxItemText {
        try PreparedInboxItemText(
            title: PersistedFieldValidator.requiredSingleLine(title, field: .inboxTitle),
            notes: PersistedFieldValidator.optionalMultiline(
                notes,
                field: .inboxNotes,
                trimsOuterWhitespace: false
            ),
            suggestionReason: PersistedFieldValidator.optionalMultiline(
                suggestionReason,
                field: .suggestionReason,
                trimsOuterWhitespace: true
            )
        )
    }

    static func prepareSuggestion(
        reason: String?,
        iconName: String,
        colorHex: String,
        modelID: String?,
        titleSnapshot: String
    ) throws -> PreparedInboxSuggestionText {
        let preparedIconName = try PersistedFieldValidator.optionalSingleLine(
            iconName,
            field: .suggestionIcon
        )
        let preparedColorHex = try PersistedFieldValidator.optionalSingleLine(
            colorHex,
            field: .suggestionColor
        )
        return try PreparedInboxSuggestionText(
            reason: PersistedFieldValidator.optionalMultiline(
                reason,
                field: .suggestionReason,
                trimsOuterWhitespace: true
            ),
            iconName: ChecklistVisualSanitizer.sanitizedIcon(preparedIconName),
            colorHex: ChecklistVisualSanitizer.sanitizedColor(preparedColorHex),
            modelID: PersistedFieldValidator.optionalSingleLine(modelID, field: .suggestionModel),
            titleSnapshot: PersistedFieldValidator.requiredSingleLine(
                titleSnapshot,
                field: .suggestionTitle
            )
        )
    }
}
