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
