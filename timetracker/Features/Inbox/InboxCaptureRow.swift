import SwiftUI

struct InboxCaptureRow: View {
    @Binding var title: String
    let placeholder: String
    var focusToken: Int
    let isCompact: Bool
    let submit: () -> Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: addButtonTapped) {
                Image(systemName: "plus")
                    .font(.system(size: isCompact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: isCompact ? 26 : 34, height: isCompact ? 26 : 34)
                    .background(.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.add"))
            .accessibilityIdentifier("inbox.capture.add")

            TextField(placeholder, text: $title)
                .textFieldStyle(.automatic)
                .font(.body)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submitIfNeeded)
                .labelsHidden()
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier("inbox.capture.title")

            Spacer(minLength: 8)

            Image(systemName: "keyboard")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: isCompact ? 48 : 52)
        .background(
            RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
                .fill(AppColors.cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
                .stroke(AppColors.border)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .accessibilityElement(children: .contain)
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
