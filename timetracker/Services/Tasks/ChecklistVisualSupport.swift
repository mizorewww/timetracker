import Foundation

enum ChecklistVisualSanitizer {
    nonisolated static let defaultIcon = "checkmark.circle"
    nonisolated static let defaultColor = "1677FF"

    nonisolated static func sanitizedIcon(_ iconName: String?) -> String {
        let trimmed = iconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              SymbolCatalog.symbolNameSet.contains(trimmed)
        else {
            return defaultIcon
        }
        return trimmed
    }

    nonisolated static func sanitizedColor(_ colorHex: String?, fallback: String? = nil) -> String {
        [colorHex, fallback, defaultColor]
            .lazy
            .compactMap(TaskColorPalette.normalizedHex)
            .first ?? defaultColor
    }

    nonisolated static func isDefault(iconName: String?, colorHex: String?) -> Bool {
        sanitizedIcon(iconName) == defaultIcon &&
            sanitizedColor(colorHex) == defaultColor
    }
}

struct ChecklistVisualSuggestionPolicy {
    func shouldSuggest(item: ChecklistItem, visual: ChecklistItemVisual?) -> Bool {
        let title = normalizedTitle(item.title)
        guard item.deletedAt == nil,
              item.isCompleted == false,
              title.isEmpty == false
        else {
            return false
        }
        guard let visual else { return true }
        guard visual.deletedAt == nil,
              visual.userEditedAt == nil
        else {
            return false
        }
        if visual.suggestionTitleSnapshot == title,
           visual.suggestionGeneratedAt != nil
        {
            return false
        }
        if visual.suggestionTitleSnapshot != nil {
            return true
        }
        return ChecklistVisualSanitizer.isDefault(
            iconName: visual.iconName,
            colorHex: visual.colorHex
        )
    }

    func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
