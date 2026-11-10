import Foundation

enum SymbolCatalog {
    nonisolated static let symbolNames: [String] = {
        let loaded = loadSymbolOrder()
        if !loaded.isEmpty {
            return loaded
        }
        return curatedSymbols
    }()

    nonisolated static let symbolNameSet = Set(symbolNames)

    nonisolated static let searchKeywords: [String: [String]] = loadSearchKeywords()

    private nonisolated static func loadSymbolOrder() -> [String] {
        guard let url = Bundle.main.url(forResource: "SFSymbolOrder", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let names = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String],
              !names.isEmpty
        else {
            return []
        }
        return Array(NSOrderedSet(array: names).compactMap { $0 as? String })
    }

    private nonisolated static func loadSearchKeywords() -> [String: [String]] {
        guard let url = Bundle.main.url(forResource: "SFSymbolSearch", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let keywords = try? PropertyListSerialization.propertyList(
                  from: data,
                  format: nil
              ) as? [String: [String]]
        else {
            return [:]
        }
        return keywords
    }

    nonisolated static let curatedSymbols = [
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
