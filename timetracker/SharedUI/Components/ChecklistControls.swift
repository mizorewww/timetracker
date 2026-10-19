import SwiftUI

enum ChecklistInputTextNormalizer {
    static func collapsingNewlines(in text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChecklistCompletionButton: View {
    let isCompleted: Bool
    var colorHex: String = ChecklistVisualSanitizer.defaultColor
    var visualSize: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChecklistCompletionMark(
                isCompleted: isCompleted,
                colorHex: colorHex,
                visualSize: visualSize
            )
            .frame(
                minWidth: AppLayout.minimumInteractiveTarget,
                minHeight: AppLayout.minimumInteractiveTarget
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.localized("editor.checklist.completionControl"))
        .accessibilityValue(
            AppStrings.localized(
                isCompleted
                    ? "editor.checklist.state.completed"
                    : "editor.checklist.state.incomplete"
            )
        )
        .accessibilityHint(
            AppStrings.localized(
                isCompleted
                    ? "editor.checklist.action.markIncomplete"
                    : "editor.checklist.action.markComplete"
            )
        )
    }
}

struct ChecklistCompletionMark: View {
    let isCompleted: Bool
    var colorHex: String = ChecklistVisualSanitizer.defaultColor
    var visualSize: CGFloat = 30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let sanitizedColor = ChecklistVisualSanitizer.sanitizedColor(colorHex)
        ZStack {
            Circle()
                .strokeBorder(.secondary.opacity(0.55), lineWidth: 1.6)
                .opacity(isCompleted ? 0 : 1)
                .scaleEffect(isCompleted ? 0.76 : 1)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: visualSize, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    TaskColorPalette.contrastingForegroundColor(for: sanitizedColor),
                    Color(hex: sanitizedColor) ?? .green
                )
                .opacity(isCompleted ? 1 : 0)
                .scaleEffect(isCompleted ? 1 : 0.76)
        }
        .frame(width: visualSize, height: visualSize)
        .contentShape(Circle())
        .animation(
            reduceMotion ? nil : AppMotion.stateChange,
            value: isCompleted
        )
        .accessibilityHidden(true)
    }
}

enum ChecklistItemIconStyle {
    case tinted
    case solid
}

struct ChecklistItemIcon: View {
    let iconName: String
    let colorHex: String
    var style: ChecklistItemIconStyle = .tinted

    var body: some View {
        let sanitizedColor = ChecklistVisualSanitizer.sanitizedColor(colorHex)
        let color = Color(hex: sanitizedColor) ?? .blue
        let foregroundColor = style == .solid
            ? TaskColorPalette.contrastingForegroundColor(for: sanitizedColor)
            : color
        let backgroundColor = style == .solid ? color : color.opacity(0.12)

        Image(systemName: ChecklistVisualSanitizer.sanitizedIcon(iconName))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: 30, height: 30)
            .background(
                backgroundColor,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// Shared checklist title field used by the inbox row, the task detail
/// editor, and the editable checklist row: plain style, completion
/// strikethrough, and newline-to-submit normalization. Focus is applied by
/// the caller with `.focused` so each surface keeps its own focus model.
struct ChecklistTitleTextField: View {
    @Binding var title: String
    let isCompleted: Bool
    var placeholder: String = AppStrings.localized("editor.checklist.itemPlaceholder")
    var boundedLineLimit: ClosedRange<Int>? = 1 ... 5
    var accessibilityIdentifier: String?
    let submit: () -> Void

    var body: some View {
        lineLimitedTextField
            .textFieldStyle(.plain)
            .strikethrough(isCompleted)
            .foregroundStyle(isCompleted ? .secondary : .primary)
            .submitLabel(.done)
            .onSubmit(submit)
            .labelsHidden()
            .accessibilityLabel(placeholder)
            .accessibilityIdentifier(optional: accessibilityIdentifier)
            .onChange(of: title) { _, newValue in
                guard newValue.contains(where: \.isNewline) else { return }
                title = ChecklistInputTextNormalizer.collapsingNewlines(
                    in: newValue
                )
                submit()
            }
    }

    @ViewBuilder
    private var lineLimitedTextField: some View {
        if let boundedLineLimit {
            baseTextField.lineLimit(boundedLineLimit)
        } else {
            baseTextField.lineLimit(nil)
        }
    }

    private var baseTextField: some View {
        TextField(placeholder, text: $title, axis: .vertical)
    }
}

private extension View {
    @ViewBuilder
    func accessibilityIdentifier(optional identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}
