import SwiftUI

struct InboxCaptureRow: View {
    @Binding var title: String
    let placeholder: String
    var focusToken: Int
    let submit: () -> Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: addButtonTapped) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(
                        AppStrings.localized(
                            canSubmit ? "inbox.add" : "inbox.capture.start"
                        )
                    )
                )
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
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityIdentifier("inbox.capture.validation")
            }
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
        guard canSubmit else { return }
        _ = submit()
        isFocused = true
    }

    private func addButtonTapped() {
        if canSubmit {
            _ = submit()
        }
        isFocused = true
    }

    private var canSubmit: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            validationMessage == nil
    }

    private var validationMessage: String? {
        guard title.isEmpty == false else { return nil }
        do {
            _ = try InboxPersistencePolicy.prepareItem(
                title: title,
                notes: nil,
                suggestionReason: nil
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
