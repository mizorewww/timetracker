import SwiftUI

/// Opens the shared symbol & color picker with a custom label, mirroring the
/// platform conventions of `SymbolColorPickerButton` (push on iOS, popover on
/// macOS).
struct SymbolColorPickerPresentation<Label: View>: View {
    @Binding var symbolName: String
    @Binding var colorHex: String
    var pickerAccessibilityIdentifier: String = "symbol.picker.open"
    var onOpen: () -> Void = {}
    @ViewBuilder var label: Label
    #if os(macOS)
    @State private var isPickerPresented = false
    #endif

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        Button {
            onOpen()
            isPickerPresented = true
        } label: {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.localized("editor.symbol.title"))
        .accessibilityValue(TaskColorPalette.accessibilityName(for: colorHex))
        .accessibilityIdentifier(pickerAccessibilityIdentifier)
        .popover(isPresented: $isPickerPresented) {
            picker.frame(width: 460, height: 520)
        }
        #else
        NavigationLink {
            picker
                .onAppear(perform: onOpen)
                .navigationTitle(AppStrings.localized("editor.symbol.title"))
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            label
        }
        .accessibilityLabel(AppStrings.localized("editor.symbol.title"))
        .accessibilityValue(TaskColorPalette.accessibilityName(for: colorHex))
        .accessibilityIdentifier(pickerAccessibilityIdentifier)
        #endif
    }

    private var picker: some View {
        SymbolAndColorPicker(
            symbols: SymbolCatalog.symbolNames,
            searchKeywords: SymbolCatalog.searchKeywords,
            symbolName: $symbolName,
            colorHex: $colorHex
        )
    }
}

struct SymbolColorPickerButton: View {
    @Binding var symbolName: String
    @Binding var colorHex: String
    var titleKey: String = "common.choose"
    var showsTitle: Bool = true
    var pickerAccessibilityIdentifier: String = "symbol.picker.open"
    var onOpen: () -> Void = {}

    var body: some View {
        SymbolColorPickerPresentation(
            symbolName: $symbolName,
            colorHex: $colorHex,
            pickerAccessibilityIdentifier: pickerAccessibilityIdentifier,
            onOpen: onOpen
        ) {
            pickerLabel
        }
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
}

struct SymbolAndColorPicker: View {
    let symbols: [String]
    let searchKeywords: [String: [String]]
    @Binding var symbolName: String
    @Binding var colorHex: String
    @State private var searchText = ""
    @State private var filteredSymbols: [String]
    @FocusState private var isSearchFocused: Bool

    init(
        symbols: [String],
        searchKeywords: [String: [String]],
        symbolName: Binding<String>,
        colorHex: Binding<String>
    ) {
        self.symbols = symbols
        self.searchKeywords = searchKeywords
        _symbolName = symbolName
        _colorHex = colorHex
        _filteredSymbols = State(initialValue: symbols)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(.app("editor.symbol.sfSymbols"))
                    .font(.headline)
                    .accessibilityIdentifier("symbol.picker.view")
                Spacer()
                SymbolColorWell(
                    selection: $colorHex,
                    onSelect: dismissSearchKeyboard
                )
                Text("\(filteredSymbols.count) / \(symbols.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextField(AppStrings.localized("editor.symbol.search"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .submitLabel(.done)
                .onSubmit(dismissSearchKeyboard)
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
                                    dismissSearchKeyboard()
                                    symbolName = symbol
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.title3)
                                        .foregroundStyle(
                                            symbolName == symbol
                                                ? TaskColorPalette.contrastingForegroundColor(for: colorHex)
                                                : (Color(hex: colorHex) ?? .blue)
                                        )
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
            .accessibilityIdentifier("symbol.picker.symbols")
            .layoutPriority(1)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif

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

    private func dismissSearchKeyboard() {
        isSearchFocused = false
    }
}
