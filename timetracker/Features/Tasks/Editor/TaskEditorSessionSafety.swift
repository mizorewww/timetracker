import SwiftUI

/// Keep/Reload choice for a draft whose save was rejected because the
/// persisted task changed on another device or scene.
private struct TaskEditorStaleDraftAlertModifier: ViewModifier {
    let session: TaskEditorSession
    let reload: () -> Void

    func body(content: Content) -> some View {
        content
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
    func taskEditorStaleDraftAlert(
        session: TaskEditorSession,
        reload: @escaping () -> Void
    ) -> some View {
        modifier(
            TaskEditorStaleDraftAlertModifier(
                session: session,
                reload: reload
            )
        )
    }
}
