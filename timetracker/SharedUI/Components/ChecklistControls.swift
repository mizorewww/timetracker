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

struct ChecklistDisplayRow: View {
    let title: String
    let isCompleted: Bool
    var iconName: String = ChecklistVisualSanitizer.defaultIcon
    var colorHex: String = ChecklistVisualSanitizer.defaultColor
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                ChecklistCompletionMark(isCompleted: isCompleted, colorHex: colorHex)
                    .padding(.top, 1)
                ChecklistItemIcon(iconName: iconName, colorHex: colorHex)
                    .padding(.top, 1)

                Text(title)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(isCompleted)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
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

struct InlineChecklistAddRow: View {
    @Binding var title: String
    var placeholder: String = AppStrings.localized("editor.checklist.itemPlaceholder")
    var focusToken: Int = 0
    let submit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(submitIfNeeded)
                .submitLabel(.done)
                .labelsHidden()
                .accessibilityLabel(placeholder)
        }
        .frame(minHeight: 44)
        .onChange(of: focusToken) { _, _ in
            isFocused = true
        }
        .onChange(of: title) { _, newValue in
            guard newValue.contains(where: \.isNewline) else { return }
            title = ChecklistInputTextNormalizer.collapsingNewlines(in: newValue)
            submitIfNeeded()
        }
    }

    private func submitIfNeeded() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit()
        title = ""
        isFocused = true
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

struct EditableChecklistTextRow: View {
    @Binding var title: String
    let isCompleted: Bool
    var iconName: String = ChecklistVisualSanitizer.defaultIcon
    var colorHex: String = ChecklistVisualSanitizer.defaultColor
    var placeholder: String = AppStrings.localized("editor.checklist.itemPlaceholder")
    var showsIcon = true
    var completionVisualSize: CGFloat = 30
    var textStyle: Font = .subheadline
    var contentAlignment: VerticalAlignment = .top
    var completionAccessibilityIdentifier: String?
    var textFieldAccessibilityIdentifier: String?
    let toggle: () -> Void
    let commit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: contentAlignment, spacing: 10) {
            completionButton
            if showsIcon {
                ChecklistItemIcon(iconName: iconName, colorHex: colorHex)
                    .padding(.top, 1)
            }

            titleField
        }
        .font(textStyle)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commit()
            }
        }
    }

    @ViewBuilder
    private var completionButton: some View {
        if let completionAccessibilityIdentifier {
            baseCompletionButton
                .accessibilityIdentifier(completionAccessibilityIdentifier)
        } else {
            baseCompletionButton
        }
    }

    private var baseCompletionButton: some View {
        ChecklistCompletionButton(
            isCompleted: isCompleted,
            colorHex: colorHex,
            visualSize: completionVisualSize
        ) {
            commit()
            toggle()
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private var titleField: some View {
        if let textFieldAccessibilityIdentifier {
            baseTitleField
                .accessibilityIdentifier(textFieldAccessibilityIdentifier)
        } else {
            baseTitleField
        }
    }

    private var baseTitleField: some View {
        ChecklistTitleTextField(
            title: $title,
            isCompleted: isCompleted,
            placeholder: placeholder,
            submit: commit
        )
        .focused($isFocused)
    }
}
