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

    nonisolated static let searchKeywords: [String: [String]] = loadSearchKeywords()

    private nonisolated static func loadSymbolOrder() -> [String] {
        for url in resourceURLs(fileName: "symbol_order", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let names = try? PropertyListSerialization.propertyList(
                      from: data,
                      format: nil
                  ) as? [String],
                  !names.isEmpty
            else {
                continue
            }
            return Array(NSOrderedSet(array: names).compactMap { $0 as? String })
        }
        return []
    }

    private nonisolated static func loadSearchKeywords() -> [String: [String]] {
        for url in resourceURLs(fileName: "symbol_search", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let keywords = try? PropertyListSerialization.propertyList(
                      from: data,
                      format: nil
                  ) as? [String: [String]]
            else {
                continue
            }
            return keywords
        }
        return [:]
    }

    private nonisolated static func resourceURLs(
        fileName: String,
        extension ext: String
    ) -> [URL] {
        let bundled: [URL] = [
            fileName == "symbol_order"
                ? Bundle.main.url(forResource: "SFSymbolOrder", withExtension: ext)
                : nil,
            fileName == "symbol_search"
                ? Bundle.main.url(forResource: "SFSymbolSearch", withExtension: ext)
                : nil,
        ].compactMap(\.self)

        let system = [
            "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/CoreServices/CoreGlyphs.bundle/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphsPrivate.bundle/Contents/Resources",
        ].map {
            URL(fileURLWithPath: $0)
                .appendingPathComponent(fileName)
                .appendingPathExtension(ext)
        }

        return bundled + system
    }

    private nonisolated static let fallbackSymbols = [
        "checkmark.circle", "folder", "briefcase", "book", "macwindow",
        "square.grid.2x2", "chevron.left.forwardslash.chevron.right",
        "person.2", "pencil.and.list.clipboard", "target", "calendar",
        "clock", "timer", "paintbrush", "chart.bar", "doc.text",
        "hammer", "lightbulb", "paperplane", "terminal", "keyboard",
        "graduationcap", "heart", "house", "cart", "creditcard",
        "briefcase.fill", "star", "tag", "tray", "archivebox", "trash",
        "play.fill", "stop.fill", "plus", "magnifyingglass",
    ]
}
