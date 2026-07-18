import BlossomColorPicker
#if os(iOS)
import BlossomColorPickerCore
#endif
import SwiftUI

enum SymbolBlossomTouchMetrics {
    static let targetDiameter: CGFloat = 44
    static let innerPetalCount = 6
    static let outerPetalCount = 12
    static let innerRadius: CGFloat = 44
    static let outerRadius: CGFloat = 88

    static func adjacentCenterSpacing(
        radius: CGFloat,
        count: Int
    ) -> CGFloat {
        2 * radius * sin(.pi / CGFloat(count))
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
            ExpandedBlossomView(model: model, layout: Self.touchLayout)
                .blossomStyle(Self.touchStyle)
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
    private static let touchLayout = PetalLayout(
        innerPetalCount: SymbolBlossomTouchMetrics.innerPetalCount,
        outerPetalCount: SymbolBlossomTouchMetrics.outerPetalCount,
        innerRadius: SymbolBlossomTouchMetrics.innerRadius,
        outerRadius: SymbolBlossomTouchMetrics.outerRadius
    )
    private static let touchStyle = BlossomStyle(
        petalSize: SymbolBlossomTouchMetrics.targetDiameter,
        innerPetalSize: SymbolBlossomTouchMetrics.targetDiameter,
        outerRingBorderWidth: 8,
        centerCircleSize: SymbolBlossomTouchMetrics.targetDiameter,
        sliderWidth: 18
    )
    private static let touchSize = ExpandedBlossomView.totalSize(
        layout: touchLayout,
        style: touchStyle
    )
    #endif
}
