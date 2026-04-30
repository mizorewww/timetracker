import SwiftUI

struct SymbolColorPickerRow: View {
    let colors: [String]
    let titleKey: String
    @Binding var symbolName: String
    @Binding var colorHex: String
    @State private var isPickerPresented = false

    init(
        colors: [String],
        titleKey: String = "editor.task.symbolColor",
        symbolName: Binding<String>,
        colorHex: Binding<String>
    ) {
        self.colors = colors
        self.titleKey = titleKey
        _symbolName = symbolName
        _colorHex = colorHex
    }

    var body: some View {
        HStack {
            Text(.app(titleKey))
            Spacer()
            pickerButton
        }
        #if os(macOS)
        .popover(isPresented: $isPickerPresented) {
            picker.frame(width: 460, height: 520)
        }
        #else
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                picker
                    .navigationTitle(AppStrings.localized("editor.symbol.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppStrings.done) {
                                isPickerPresented = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        #endif
    }

    private var pickerButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(Color(hex: colorHex) ?? .blue)
                Text(.app("common.choose"))
            }
        }
    }

    private var picker: some View {
        SymbolAndColorPicker(
            symbols: SymbolCatalog.symbolNames,
            searchKeywords: SymbolCatalog.searchKeywords,
            colors: colors,
            symbolName: $symbolName,
            colorHex: $colorHex
        )
    }
}

struct SymbolAndColorPicker: View {
    let symbols: [String]
    let searchKeywords: [String: [String]]
    let colors: [String]
    @Binding var symbolName: String
    @Binding var colorHex: String
    @State private var searchText = ""

    private var filteredSymbols: [String] {
        guard !searchText.isEmpty else { return symbols }
        return symbols.filter { symbol in
            symbol.localizedCaseInsensitiveContains(searchText) ||
            (searchKeywords[symbol]?.contains { $0.localizedCaseInsensitiveContains(searchText) } ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(.app("editor.symbol.sfSymbols"))
                    .font(.headline)
                Spacer()
                Text("\(filteredSymbols.count) / \(symbols.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextField(AppStrings.localized("editor.symbol.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 8)], spacing: 8) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button {
                            symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .foregroundStyle(symbolName == symbol ? .white : (Color(hex: colorHex) ?? .blue))
                                .frame(width: 38, height: 38)
                                .background(symbolName == symbol ? (Color(hex: colorHex) ?? .blue) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            Text(.app("editor.symbol.color"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .blue)
                            .frame(width: 26, height: 26)
                            .overlay {
                                if colorHex == hex {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(format: AppStrings.localized("editor.symbol.colorValue"), hex))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum SymbolCatalog {
    static let symbolNames: [String] = {
        let loaded = loadSymbolOrder()
        if !loaded.isEmpty {
            return loaded
        }
        return fallbackSymbols
    }()

    static let searchKeywords: [String: [String]] = loadSearchKeywords()

    private static func loadSymbolOrder() -> [String] {
        for url in resourceURLs(fileName: "symbol_order", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let names = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String],
                  !names.isEmpty else {
                continue
            }
            return Array(NSOrderedSet(array: names).compactMap { $0 as? String })
        }
        return []
    }

    private static func loadSearchKeywords() -> [String: [String]] {
        for url in resourceURLs(fileName: "symbol_search", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let keywords = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] else {
                continue
            }
            return keywords
        }
        return [:]
    }

    private static func resourceURLs(fileName: String, extension ext: String) -> [URL] {
        let bundled: [URL] = [
            fileName == "symbol_order" ? Bundle.main.url(forResource: "SFSymbolOrder", withExtension: ext) : nil,
            fileName == "symbol_search" ? Bundle.main.url(forResource: "SFSymbolSearch", withExtension: ext) : nil
        ].compactMap(\.self)

        let system = [
            "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/CoreServices/CoreGlyphs.bundle/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphs.bundle/Contents/Resources",
            "/System/Library/PrivateFrameworks/SFSymbols.framework/Versions/A/Resources/CoreGlyphsPrivate.bundle/Contents/Resources"
        ].map {
            URL(fileURLWithPath: $0).appendingPathComponent(fileName).appendingPathExtension(ext)
        }

        return bundled + system
    }

    private static let fallbackSymbols = [
        "checkmark.circle", "folder", "briefcase", "book", "macwindow",
        "square.grid.2x2", "chevron.left.forwardslash.chevron.right",
        "person.2", "pencil.and.list.clipboard", "target", "calendar",
        "clock", "timer", "paintbrush", "chart.bar", "doc.text",
        "hammer", "lightbulb", "paperplane", "terminal", "keyboard",
        "graduationcap", "heart", "house", "cart", "creditcard",
        "briefcase.fill", "star", "tag", "tray", "archivebox", "trash",
        "play.fill", "pause.fill", "stop.fill", "plus", "magnifyingglass"
    ]
}
