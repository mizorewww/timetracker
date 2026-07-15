import SwiftUI

struct InboxCaptureRow: View {
    @Binding var title: String
    let placeholder: String
    var focusToken: Int
    let submit: () -> Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: addButtonTapped) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(.blue, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.add"))
            .accessibilityIdentifier("inbox.capture.add")

            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submitIfNeeded)
                .labelsHidden()
                .accessibilityLabel(AppStrings.localized("inbox.addPlaceholder"))
                .accessibilityHint(AppStrings.localized("inbox.capture.hint"))
                .accessibilityIdentifier("inbox.capture.field")
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
        if submit() {
            title = ""
        }
        isFocused = true
    }

    private func addButtonTapped() {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isFocused = true
        } else {
            if submit() {
                title = ""
            }
            isFocused = true
        }
    }
}
