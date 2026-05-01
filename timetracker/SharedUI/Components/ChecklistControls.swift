import SwiftUI

struct ChecklistCompletionButton: View {
    let isCompleted: Bool
    var colorHex: String = ChecklistVisualSanitizer.defaultColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChecklistCompletionMark(isCompleted: isCompleted, colorHex: colorHex)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.localized("editor.checklist.completed"))
    }
}

struct ChecklistCompletionMark: View {
    let isCompleted: Bool
    var colorHex: String = ChecklistVisualSanitizer.defaultColor

    var body: some View {
        ZStack {
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .regular))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(hex: ChecklistVisualSanitizer.sanitizedColor(colorHex)) ?? .green)
            } else {
                Circle()
                    .strokeBorder(.secondary.opacity(0.55), lineWidth: 1.6)
            }
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .symbolEffect(.bounce, value: isCompleted)
        .animation(.snappy(duration: 0.18), value: isCompleted)
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
            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(submitIfNeeded)
                .submitLabel(.done)
                .labelsHidden()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .onChange(of: focusToken) { _, _ in
            isFocused = true
        }
    }

    private func submitIfNeeded() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit()
        isFocused = true
    }
}

struct EditableChecklistTextRow: View {
    @Binding var title: String
    let isCompleted: Bool
    var iconName: String = ChecklistVisualSanitizer.defaultIcon
    var colorHex: String = ChecklistVisualSanitizer.defaultColor
    var placeholder: String = AppStrings.localized("editor.checklist.itemPlaceholder")
    let toggle: () -> Void
    let commit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ChecklistCompletionButton(isCompleted: isCompleted, colorHex: colorHex) {
                commit()
                toggle()
            }
            .padding(.top, 1)
            ChecklistItemIcon(iconName: iconName, colorHex: colorHex)
                .padding(.top, 1)

            TextField(placeholder, text: $title, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .strikethrough(isCompleted)
                .foregroundStyle(isCompleted ? .secondary : .primary)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(commit)
                .labelsHidden()
        }
        .font(.subheadline)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onChange(of: isFocused) { _, focused in
            if !focused {
                commit()
            }
        }
        .animation(.snappy(duration: 0.18), value: isCompleted)
    }
}
