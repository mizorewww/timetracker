import SwiftUI

struct CountdownTitleEditor: View {
    let persistedTitle: String
    let onSave: (String) -> Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isTitleFocused: Bool
    @State private var draft: CountdownTitleDraft

    init(persistedTitle: String, onSave: @escaping (String) -> Bool) {
        self.persistedTitle = persistedTitle
        self.onSave = onSave
        _draft = State(initialValue: CountdownTitleDraft(persistedTitle: persistedTitle))
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsRowLabel(
                        title: AppStrings.localized("settings.countdown.eventName"),
                        systemImage: "textformat",
                        tint: .blue
                    )
                    editorValue
                }
            } else {
                LabeledContent {
                    editorValue
                } label: {
                    SettingsRowLabel(
                        title: AppStrings.localized("settings.countdown.eventName"),
                        systemImage: "textformat",
                        tint: .blue
                    )
                }
            }
        }
        .settingsRowSeparatorAligned()
        .onChange(of: persistedTitle) { _, newTitle in
            draft.reconcile(persistedTitle: newTitle)
        }
        .onChange(of: isTitleFocused) { wasFocused, isFocused in
            if wasFocused, !isFocused {
                commitTitle()
            }
        }
    }

    private var editorValue: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(
                    AppStrings.localized("settings.countdown.eventName"),
                    text: $draft.text
                )
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit(commitTitle)
                .accessibilityLabel(AppStrings.localized("settings.countdown.eventName"))
                .accessibilityHint(
                    draft.error?.localizedMessage
                        ?? AppStrings.localized("settings.countdown.title.hint")
                )
                .accessibilityIdentifier("settings.countdown.title.field")
                #if os(iOS)
                    .textInputAutocapitalization(.sentences)
                #endif

                saveButton
            }

            if let error = draft.error {
                Label(error.localizedMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityLabel(error.localizedMessage)
                    .accessibilityIdentifier("settings.countdown.title.error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        Button(AppStrings.localized("common.save"), action: commitTitle)
            .buttonStyle(.bordered)
            .frame(minWidth: minimumControlSize, minHeight: minimumControlSize)
            .disabled(!draft.isDirty)
            .opacity(draft.isDirty ? 1 : 0)
            .accessibilityHidden(!draft.isDirty)
            .accessibilityLabel(AppStrings.localized("settings.countdown.title.save"))
            .accessibilityHint(AppStrings.localized("settings.countdown.title.saveHint"))
            .accessibilityIdentifier("settings.countdown.title.save")
            .help(AppStrings.localized("settings.countdown.title.save"))
    }

    private var minimumControlSize: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }

    private func commitTitle() {
        if draft.commit(using: onSave) {
            isTitleFocused = false
        }
    }
}
