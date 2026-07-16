import SwiftUI

struct SymbolColorPickerButton: View {
    let colors: [String]
    @Binding var symbolName: String
    @Binding var colorHex: String
    var titleKey: String = "common.choose"
    var showsTitle: Bool = true
    #if os(macOS)
    @State private var isPickerPresented = false
    #endif

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        Button {
            isPickerPresented = true
        } label: {
            pickerLabel
        }
        .accessibilityLabel(AppStrings.localized("editor.symbol.title"))
        .accessibilityValue(TaskColorPalette.accessibilityName(for: colorHex))
        .accessibilityIdentifier("symbol.picker.open")
        .popover(isPresented: $isPickerPresented) {
            picker.frame(width: 460, height: 520)
        }
        #else
        NavigationLink {
            picker
                .navigationTitle(AppStrings.localized("editor.symbol.title"))
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            pickerLabel
        }
        .accessibilityLabel(AppStrings.localized("editor.symbol.title"))
        .accessibilityValue(TaskColorPalette.accessibilityName(for: colorHex))
        .accessibilityIdentifier("symbol.picker.open")
        #endif
    }

    private var pickerLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: ChecklistVisualSanitizer.sanitizedIcon(symbolName))
                .foregroundStyle(Color(hex: ChecklistVisualSanitizer.sanitizedColor(colorHex)) ?? .blue)
            if showsTitle {
                Text(.app(titleKey))
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
                .accessibilityIdentifier("symbol.picker.search")

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
                            .accessibilityIdentifier("symbol.picker.symbol.\(symbol)")
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
        .accessibilityIdentifier("symbol.picker.view")
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
