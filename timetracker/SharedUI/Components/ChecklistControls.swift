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
        }
        .buttonStyle(.plain)
        .frame(
            minWidth: AppLayout.minimumInteractiveTarget,
            minHeight: AppLayout.minimumInteractiveTarget
        )
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

    var body: some View {
        let sanitizedColor = ChecklistVisualSanitizer.sanitizedColor(colorHex)
        ZStack {
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: visualSize, weight: .regular))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        TaskColorPalette.contrastingForegroundColor(for: sanitizedColor),
                        Color(hex: sanitizedColor) ?? .green
                    )
            } else {
                Circle()
                    .strokeBorder(.secondary.opacity(0.55), lineWidth: 1.6)
            }
        }
        .frame(width: visualSize, height: visualSize)
        .contentShape(Circle())
        .accessibilityHidden(true)
    }
}

struct ChecklistItemIcon: View {
    let iconName: String
    let colorHex: String

    var body: some View {
        let color = Color(hex: ChecklistVisualSanitizer.sanitizedColor(colorHex)) ?? .blue
        Image(systemName: ChecklistVisualSanitizer.sanitizedIcon(iconName))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 30, height: 30)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

struct EditableChecklistTextRow: View {
    @Binding var title: String
    let isCompleted: Bool
    var iconName: String = ChecklistVisualSanitizer.defaultIcon
    var colorHex: String = ChecklistVisualSanitizer.defaultColor
    var placeholder: String = AppStrings.localized("editor.checklist.itemPlaceholder")
    var showsIcon = true
    var completionVisualSize: CGFloat = 30
    var textStyle: Font = .subheadline
    var textFieldAccessibilityIdentifier: String?
    let toggle: () -> Void
    let commit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ChecklistCompletionButton(
                isCompleted: isCompleted,
                colorHex: colorHex,
                visualSize: completionVisualSize
            ) {
                commit()
                toggle()
            }
            .padding(.top, 1)
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
    private var titleField: some View {
        if let textFieldAccessibilityIdentifier {
            baseTitleField
                .accessibilityIdentifier(textFieldAccessibilityIdentifier)
        } else {
            baseTitleField
        }
    }

    private var baseTitleField: some View {
        TextField(placeholder, text: $title, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .strikethrough(isCompleted)
            .foregroundStyle(isCompleted ? .secondary : .primary)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit(commit)
            .labelsHidden()
            .accessibilityLabel(placeholder)
            .onChange(of: title) { _, newValue in
                guard newValue.contains(where: \.isNewline) else { return }
                title = ChecklistInputTextNormalizer.collapsingNewlines(in: newValue)
                commit()
            }
    }
}
