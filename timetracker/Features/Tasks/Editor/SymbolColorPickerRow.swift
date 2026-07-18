import SwiftUI

struct SymbolColorPickerRow: View {
    let titleKey: String
    let pickerAccessibilityIdentifier: String
    let onOpen: () -> Void
    @Binding var symbolName: String
    @Binding var colorHex: String

    init(
        titleKey: String = "editor.task.symbolColor",
        pickerAccessibilityIdentifier: String = "symbol.picker.open.task",
        onOpen: @escaping () -> Void = {},
        symbolName: Binding<String>,
        colorHex: Binding<String>
    ) {
        self.titleKey = titleKey
        self.pickerAccessibilityIdentifier = pickerAccessibilityIdentifier
        self.onOpen = onOpen
        _symbolName = symbolName
        _colorHex = colorHex
    }

    var body: some View {
        HStack {
            Text(.app(titleKey))
            Spacer()
            SymbolColorPickerButton(
                symbolName: $symbolName,
                colorHex: $colorHex,
                pickerAccessibilityIdentifier: pickerAccessibilityIdentifier,
                onOpen: onOpen
            )
        }
    }
}
