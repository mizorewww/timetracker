import SwiftUI

extension View {
    func editorDiscardConfirmation(
        isPresented: Binding<Bool>,
        hasUnsavedChanges: Bool,
        discard: @escaping () -> Void
    ) -> some View {
        interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                AppStrings.localized("editor.discard.title"),
                isPresented: isPresented,
                titleVisibility: .visible
            ) {
                Button(AppStrings.localized("editor.discard.confirm"), role: .destructive, action: discard)
                Button(AppStrings.cancel, role: .cancel) {}
            } message: {
                Text(.app("editor.discard.message"))
            }
    }
}
