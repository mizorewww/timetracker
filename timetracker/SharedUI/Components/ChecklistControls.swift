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
