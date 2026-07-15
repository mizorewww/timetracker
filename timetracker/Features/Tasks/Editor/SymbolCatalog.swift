import Foundation

enum SymbolCatalog {
    nonisolated static let symbolNames: [String] = {
        let loaded = loadSymbolOrder()
        if !loaded.isEmpty {
            return loaded
        }
        return fallbackSymbols
    }()

    nonisolated static let symbolNameSet = Set(symbolNames)

    /// A compact, semantic vocabulary for server-backed AI suggestions.
    /// The full catalogue remains available to the on-device symbol picker.
    nonisolated static let aiSuggestionSymbolNames: [String] = curatedAISuggestionSymbols.filter {
        symbolNameSet.contains($0)
    }

    nonisolated static let aiSuggestionSymbolNameSet = Set(aiSuggestionSymbolNames)

    nonisolated static let searchKeywords: [String: [String]] = loadSearchKeywords()

    nonisolated private static func loadSymbolOrder() -> [String] {
        for url in resourceURLs(fileName: "symbol_order", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let names = try? PropertyListSerialization.propertyList(
                    from: data,
                    format: nil
                  ) as? [String],
                  !names.isEmpty else {
                continue
            }
            return Array(NSOrderedSet(array: names).compactMap { $0 as? String })
        }
        return []
    }

    nonisolated private static func loadSearchKeywords() -> [String: [String]] {
        for url in resourceURLs(fileName: "symbol_search", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let keywords = try? PropertyListSerialization.propertyList(
                    from: data,
                    format: nil
                  ) as? [String: [String]] else {
                continue
            }
            return keywords
        }
        return [:]
    }

    nonisolated private static func resourceURLs(
        fileName: String,
        extension ext: String
    ) -> [URL] {
        let bundled: [URL] = [
            fileName == "symbol_order"
                ? Bundle.main.url(forResource: "SFSymbolOrder", withExtension: ext)
                : nil,
            fileName == "symbol_search"
                ? Bundle.main.url(forResource: "SFSymbolSearch", withExtension: ext)
                : nil
        ].compactMap(\.self)

        let system = [
            "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/CoreServices/CoreGlyphs.bundle/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphsPrivate.bundle/Contents/Resources"
        ].map {
            URL(fileURLWithPath: $0)
                .appendingPathComponent(fileName)
                .appendingPathExtension(ext)
        }

        return bundled + system
    }

    nonisolated private static let fallbackSymbols = [
        "checkmark.circle", "folder", "briefcase", "book", "macwindow",
        "square.grid.2x2", "chevron.left.forwardslash.chevron.right",
        "person.2", "pencil.and.list.clipboard", "target", "calendar",
        "clock", "timer", "paintbrush", "chart.bar", "doc.text",
        "hammer", "lightbulb", "paperplane", "terminal", "keyboard",
        "graduationcap", "heart", "house", "cart", "creditcard",
        "briefcase.fill", "star", "tag", "tray", "archivebox", "trash",
        "play.fill", "stop.fill", "plus", "magnifyingglass"
    ]

    nonisolated private static let curatedAISuggestionSymbols = [
        // Planning and focus
        "checkmark.circle", "target", "calendar", "clock", "timer",
        "alarm", "flag", "bookmark", "tag", "tray", "archivebox",
        "list.bullet.clipboard", "pencil.and.list.clipboard", "repeat",
        // Work and creation
        "briefcase", "folder", "doc.text", "chart.bar", "macwindow",
        "square.grid.2x2", "chevron.left.forwardslash.chevron.right",
        "terminal", "keyboard", "hammer", "wrench.and.screwdriver",
        "gearshape", "paintbrush", "lightbulb", "paperplane",
        // Learning and communication
        "book", "graduationcap", "person", "person.2", "person.3",
        "phone", "envelope", "message", "globe", "map", "location",
        // Home, health, and daily life
        "house", "heart", "cross.case", "pills", "stethoscope",
        "figure.walk", "dumbbell", "fork.knife", "cup.and.saucer",
        "bed.double", "cart", "bag", "creditcard", "banknote",
        "gift", "birthday.cake", "car", "bicycle", "airplane",
        "tram", "shippingbox", "pawprint", "leaf",
        // Hobbies and environment
        "music.note", "film", "photo", "camera", "gamecontroller",
        "star", "sparkles", "bolt", "flame", "drop", "sun.max",
        "moon", "cloud", "snowflake", "umbrella"
    ]
}
