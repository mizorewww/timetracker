import BlossomColorPicker
import BlossomColorPickerCore
import SwiftUI

enum SymbolBlossomTouchMetrics {
    static let targetDiameter: CGFloat = 44
    static let sourcePetalDiameter = BlossomConstants.petalSize
    static let scale = targetDiameter / sourcePetalDiameter

    static func scaled(_ value: CGFloat) -> CGFloat {
        value * scale
    }
}

struct SymbolColorWell: View {
    @Binding var selection: String
    let onSelect: () -> Void
    @Environment(\.self) private var environment
    #if os(iOS)
    @State private var isPresented = false
    @State private var model: BlossomColorPickerModel
    #endif

    init(selection: Binding<String>, onSelect: @escaping () -> Void) {
        _selection = selection
        self.onSelect = onSelect
        #if os(iOS)
        _model = State(
            initialValue: BlossomColorPickerModel(
                initialColor: TaskColorPalette.pickerColor(for: selection.wrappedValue)
            )
        )
        #endif
    }

    var body: some View {
        platformWell
            .accessibilityLabel(AppStrings.localized("editor.symbol.color"))
            .accessibilityValue(TaskColorPalette.accessibilityName(for: selection))
            .accessibilityIdentifier("symbol.picker.color.well")
    }

    @ViewBuilder
    private var platformWell: some View {
        #if os(iOS)
        Button {
            onSelect()
            model.selectedColor = TaskColorPalette.pickerColor(for: selection)
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
            ExpandedBlossomView(model: model, layout: Self.defaultLayout)
                .frame(width: Self.defaultSize, height: Self.defaultSize)
                .scaleEffect(SymbolBlossomTouchMetrics.scale)
                .frame(width: Self.touchSize, height: Self.touchSize)
                .padding(8)
                .onAppear {
                    model.expand()
                }
                .onDisappear {
                    model.collapse()
                }
                .onChange(of: model.selectedColor) { _, newColor in
                    updateSelection(from: newColor)
                }
                .onChange(of: model.isExpanded) { _, isExpanded in
                    if isExpanded == false {
                        isPresented = false
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(AppStrings.localized("editor.symbol.color"))
                .accessibilityIdentifier("symbol.picker.color.blossom")
                .presentationCompactAdaptation(.popover)
        }
        #else
        BlossomColorPicker(
            selection: colorBinding,
            onDismiss: { _ in onSelect() }
        )
        .frame(
            width: AppLayout.minimumInteractiveTarget,
            height: AppLayout.minimumInteractiveTarget
        )
        #endif
    }

    private var colorBinding: Binding<Color> {
        Binding {
            TaskColorPalette.pickerColor(for: selection)
        } set: { newColor in
            updateSelection(from: newColor)
        }
    }

    private func updateSelection(from color: Color) {
        let resolved = color.resolve(in: environment)
        selection = TaskColorPalette.hex(
            red: resolved.red,
            green: resolved.green,
            blue: resolved.blue
        )
        onSelect()
    }

    #if os(iOS)
    private static let defaultLayout = PetalLayout()
    private static let defaultSize = ExpandedBlossomView.totalSize(
        layout: defaultLayout
    )
    private static let touchSize = SymbolBlossomTouchMetrics.scaled(defaultSize)
    #endif
}
