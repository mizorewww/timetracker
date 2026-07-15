import Foundation
import SwiftUI

struct SymbolColorPickerRow: View {
    let colors: [String]
    let titleKey: String
    @Binding var symbolName: String
    @Binding var colorHex: String

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
            SymbolColorPickerButton(
                colors: colors,
                symbolName: $symbolName,
                colorHex: $colorHex
            )
        }
    }
}

struct SymbolColorPickerButton: View {
    let colors: [String]
    @Binding var symbolName: String
    @Binding var colorHex: String
    var titleKey: String = "common.choose"
    var showsTitle: Bool = true
    @State private var isPickerPresented = false

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: ChecklistVisualSanitizer.sanitizedIcon(symbolName))
                    .foregroundStyle(Color(hex: ChecklistVisualSanitizer.sanitizedColor(colorHex)) ?? .blue)
                if showsTitle {
                    Text(.app(titleKey))
                }
            }
        }
        .accessibilityLabel(AppStrings.localized("editor.symbol.title"))
        .accessibilityValue(TaskColorPalette.accessibilityName(for: colorHex))
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
    @State private var filteredSymbols: [String]

    init(
        symbols: [String],
        searchKeywords: [String: [String]],
        colors: [String],
        symbolName: Binding<String>,
        colorHex: Binding<String>
    ) {
        self.symbols = symbols
        self.searchKeywords = searchKeywords
        self.colors = colors
        _symbolName = symbolName
        _colorHex = colorHex
        _filteredSymbols = State(initialValue: symbols)
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
                Group {
                if filteredSymbols.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: AppLayout.minimumInteractiveTarget), spacing: 8)], spacing: 8) {
                        ForEach(filteredSymbols, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .foregroundStyle(symbolName == symbol ? .white : (Color(hex: colorHex) ?? .blue))
                                    .frame(
                                        width: AppLayout.minimumInteractiveTarget,
                                        height: AppLayout.minimumInteractiveTarget
                                    )
                                    .background(symbolName == symbol ? (Color(hex: colorHex) ?? .blue) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help(symbol)
                            .accessibilityLabel(
                                String.localizedStringWithFormat(
                                    AppStrings.localized("editor.symbol.symbolValue"),
                                    symbol
                                )
                            )
                            .accessibilityAddTraits(symbolName == symbol ? .isSelected : [])
                        }
                    }
                }
                }
                .padding(.vertical, 2)
            }

            Divider()

            Text(.app("editor.symbol.color"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: AppLayout.minimumInteractiveTarget), spacing: 10)], alignment: .leading, spacing: 10) {
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
                            .frame(
                                width: AppLayout.minimumInteractiveTarget,
                                height: AppLayout.minimumInteractiveTarget
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String.localizedStringWithFormat(
                            AppStrings.localized("editor.symbol.colorValue"),
                            TaskColorPalette.accessibilityName(for: hex)
                        )
                    )
                    .accessibilityAddTraits(colorHex == hex ? .isSelected : [])
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: searchText, initial: true) { _, query in
            updateFilteredSymbols(query: query)
        }
        .onChange(of: symbols) { _, _ in
            updateFilteredSymbols(query: searchText)
        }
    }

    private func updateFilteredSymbols(query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            filteredSymbols = symbols
            return
        }
        filteredSymbols = symbols.filter { symbol in
            symbol.localizedCaseInsensitiveContains(normalizedQuery) ||
                (searchKeywords[symbol]?.contains {
                    $0.localizedCaseInsensitiveContains(normalizedQuery)
                } ?? false)
        }
    }
}

enum SymbolCatalog {
    nonisolated static let symbolNames: [String] = {
        let loaded = loadSymbolOrder()
        if !loaded.isEmpty {
            return loaded
        }
        return fallbackSymbols
    }()

    nonisolated static let searchKeywords: [String: [String]] = loadSearchKeywords()

    nonisolated private static func loadSymbolOrder() -> [String] {
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

    nonisolated private static func loadSearchKeywords() -> [String: [String]] {
        for url in resourceURLs(fileName: "symbol_search", extension: "plist") {
            guard let data = try? Data(contentsOf: url),
                  let keywords = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] else {
                continue
            }
            return keywords
        }
        return [:]
    }

    nonisolated private static func resourceURLs(fileName: String, extension ext: String) -> [URL] {
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
}
