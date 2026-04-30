import SwiftUI

struct ChecklistCompletionButton: View {
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChecklistCompletionMark(isCompleted: isCompleted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.localized("editor.checklist.completed"))
    }
}

struct ChecklistCompletionMark: View {
    let isCompleted: Bool

    var body: some View {
        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 28, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isCompleted ? .green : .secondary)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
    }
}

struct ChecklistDisplayRow: View {
    let title: String
    let isCompleted: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                ChecklistCompletionMark(isCompleted: isCompleted)
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
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

struct InlineChecklistAddRow: View {
    @Binding var title: String
    let submit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
            TextField(AppStrings.localized("editor.checklist.itemPlaceholder"), text: $title)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(submitIfNeeded)
                .submitLabel(.done)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
    }

    private func submitIfNeeded() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit()
        isFocused = true
    }
}
