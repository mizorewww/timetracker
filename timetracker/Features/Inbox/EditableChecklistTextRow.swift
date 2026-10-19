import SwiftUI

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
    /// The persisted title; adopted into `title` whenever it changes while
    /// the field is not being edited, so a remote edit never clobbers typing.
    var persistedTitle: String?
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
        .onChange(of: persistedTitle, initial: true) { _, persisted in
            guard let persisted, isFocused == false else { return }
            title = persisted
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
