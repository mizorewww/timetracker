import SwiftUI

private struct TaskEditorSessionSafetyModifier: ViewModifier {
    let session: TaskEditorSession
    let discard: () -> Void
    let reload: () -> Void

    func body(content: Content) -> some View {
        @Bindable var session = session

        content
            .editorDiscardConfirmation(
                isPresented: $session.isDiscardConfirmationPresented,
                hasUnsavedChanges: session.hasUnsavedChanges,
                discard: discard
            )
            .alert(
                AppStrings.localized("task.editor.stale.title"),
                isPresented: reloadAlertBinding
            ) {
                Button(
                    AppStrings.localized("task.editor.stale.reload"),
                    role: .destructive,
                    action: reload
                )
                Button(
                    AppStrings.localized("task.editor.stale.keepEditing"),
                    role: .cancel
                ) {
                    session.pendingReloadDraft = nil
                }
            } message: {
                Text(.app("task.editor.stale.reloadMessage"))
            }
    }

    private var reloadAlertBinding: Binding<Bool> {
        Binding(
            get: { session.pendingReloadDraft != nil },
            set: { isPresented in
                if isPresented == false {
                    session.pendingReloadDraft = nil
                }
            }
        )
    }
}

extension View {
    func taskEditorSessionSafety(
        session: TaskEditorSession,
        discard: @escaping () -> Void,
        reload: @escaping () -> Void
    ) -> some View {
        modifier(
            TaskEditorSessionSafetyModifier(
                session: session,
                discard: discard,
                reload: reload
            )
        )
    }
}
