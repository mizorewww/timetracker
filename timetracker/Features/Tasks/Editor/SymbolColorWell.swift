import SwiftUI

struct SymbolColorWell: View {
    @Binding var selection: String
    let onSelect: () -> Void
    @Environment(\.self) private var environment
    @State private var isPresented = false

    init(selection: Binding<String>, onSelect: @escaping () -> Void) {
        _selection = selection
        self.onSelect = onSelect
    }

    var body: some View {
        Button {
            onSelect()
            isPresented = true
        } label: {
            Circle()
                .fill(TaskColorPalette.pickerColor(for: selection))
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.6), lineWidth: 1)
                }
                .frame(
                    width: AppLayout.minimumInteractiveTarget,
                    height: AppLayout.minimumInteractiveTarget
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            palettePopover
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(AppStrings.localized("editor.symbol.color"))
        .accessibilityValue(TaskColorPalette.accessibilityName(for: selection))
        .accessibilityIdentifier("symbol.picker.color.well")
    }

    private var palettePopover: some View {
        let normalizedSelection = TaskColorPalette.normalizedHex(selection)
        let columns = Array(
            repeating: GridItem(.fixed(AppLayout.minimumInteractiveTarget), spacing: 8),
            count: 6
        )

        return VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(TaskColorPalette.hexValues, id: \.self) { hex in
                    let isSelected = normalizedSelection == hex
                    Button {
                        selection = hex
                        onSelect()
                        isPresented = false
                    } label: {
                        Circle()
                            .fill(TaskColorPalette.pickerColor(for: hex))
                            .frame(width: 32, height: 32)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(
                                            TaskColorPalette.contrastingForegroundColor(for: hex)
                                        )
                                } else {
                                    Circle()
                                        .stroke(.primary.opacity(0.15), lineWidth: 1)
                                }
                            }
                            .frame(
                                width: AppLayout.minimumInteractiveTarget,
                                height: AppLayout.minimumInteractiveTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(TaskColorPalette.accessibilityName(for: hex))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("symbol.picker.color.swatch.\(hex)")
                }
            }

            Divider()

            ColorPicker(
                AppStrings.localized("editor.symbol.color"),
                selection: customColorBinding,
                supportsOpacity: false
            )
            .font(.subheadline)
        }
        .padding(14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStrings.localized("editor.symbol.color"))
        .accessibilityIdentifier("symbol.picker.color.palette")
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { TaskColorPalette.pickerColor(for: selection) },
            set: { newColor in
                let resolved = newColor.resolve(in: environment)
                selection = TaskColorPalette.hex(
                    red: resolved.red,
                    green: resolved.green,
                    blue: resolved.blue
                )
                onSelect()
            }
        )
    }
}
