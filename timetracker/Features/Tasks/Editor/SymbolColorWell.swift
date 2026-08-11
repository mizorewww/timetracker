import BlossomColorPickerCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.self) private var environment
    @State private var isPresented = false
    @State private var model: BlossomColorPickerModel
    #if os(macOS)
    @State private var anchorView: NSView?
    @State private var presenter = MacBlossomColorPresenter()
    #endif

    init(selection: Binding<String>, onSelect: @escaping () -> Void) {
        _selection = selection
        self.onSelect = onSelect
        _model = State(
            initialValue: BlossomColorPickerModel(
                initialColor: TaskColorPalette.pickerColor(for: selection.wrappedValue)
            )
        )
    }

    var body: some View {
        platformWell
            .onChange(of: model.selectedColor) { _, newColor in
                updateSelection(from: newColor)
            }
            .onChange(of: model.isExpanded) { _, isExpanded in
                if isExpanded == false {
                    isPresented = false
                    #if os(macOS)
                    presenter.dismiss()
                    #endif
                }
            }
            .onDisappear {
                model.collapse()
                #if os(macOS)
                presenter.dismissImmediately()
                #endif
            }
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
                .transaction { transaction in
                    if reduceMotion {
                        transaction.disablesAnimations = true
                    }
                }
                .onAppear {
                    model.expand()
                }
                .onDisappear {
                    model.collapse()
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(AppStrings.localized("editor.symbol.color"))
                .accessibilityIdentifier("symbol.picker.color.blossom")
                .presentationCompactAdaptation(.popover)
        }
        #else
        Button {
            onSelect()
            model.selectedColor = TaskColorPalette.pickerColor(for: selection)
            guard let anchorView,
                  presenter.show(
                      relativeTo: anchorView,
                      model: model,
                      layout: Self.defaultLayout,
                      reduceMotion: reduceMotion
                  )
            else {
                return
            }
            isPresented = true
        } label: {
            Circle()
                .fill(TaskColorPalette.pickerColor(for: selection))
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.6), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .frame(
            width: AppLayout.minimumInteractiveTarget,
            height: AppLayout.minimumInteractiveTarget
        )
        .background {
            MacBlossomAnchorReader { resolvedView in
                if anchorView !== resolvedView {
                    anchorView = resolvedView
                }
            }
        }
        #endif
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

    private static let defaultLayout = PetalLayout()
    #if os(iOS)
    private static let defaultSize = ExpandedBlossomView.totalSize(
        layout: defaultLayout
    )
    private static let touchSize = SymbolBlossomTouchMetrics.scaled(defaultSize)
    #endif
}
