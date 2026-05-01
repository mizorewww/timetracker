import Foundation

enum ChecklistVisualSanitizer {
    nonisolated static let defaultIcon = "checkmark.circle"
    nonisolated static let defaultColor = "1677FF"

    nonisolated static func sanitizedIcon(_ iconName: String?) -> String {
        let trimmed = iconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              SymbolCatalog.symbolNames.contains(trimmed) else {
            return defaultIcon
        }
        return trimmed
    }

    nonisolated static func sanitizedColor(_ colorHex: String?, fallback: String? = nil) -> String {
        let candidates = [
            colorHex?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased(),
            fallback?.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased(),
            defaultColor
        ]
        return candidates.compactMap(\.self).first { candidate in
            TaskColorPalette.hexValues.contains(candidate)
        } ?? defaultColor
    }
}
