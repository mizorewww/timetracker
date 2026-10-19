import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Debounced autosave plus a synchronous commit whenever the edit could be
/// left behind: focus leaves a field, the scene backgrounds, the detail
/// disappears (navigation), the Mac app terminates, or another surface is
/// about to change the task's lifecycle (archive).
private struct TaskDetailAutosaveModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var registrationID = UUID()

    let taskID: UUID
    let controller: TaskDetailAutosaveController
    let request: TaskDetailAutosaveRequest
    let focusedTextField: TaskEditorTextField?
    let focusedChecklistDraftID: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: request, initial: true) { _, request in
                controller.update(with: request)
            }
            .onChange(of: focusedTextField) { oldValue, newValue in
                flushWhenFocusLeaves(oldValue, newValue)
            }
            .onChange(of: focusedChecklistDraftID) { oldValue, newValue in
                flushWhenFocusLeaves(oldValue, newValue)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                flush()
            }
            .onAppear {
                presentationRouter.registerOpenTaskDetailSave(
                    id: registrationID,
                    taskID: taskID
                ) { [controller] in
                    controller.flush()
                }
            }
            .onDisappear {
                presentationRouter.unregisterOpenTaskDetailSave(id: registrationID)
                reportUnsavedEditsOnLeave()
            }
            .taskDetailAutosaveTerminationFlush(perform: flush)
    }

    private func flushWhenFocusLeaves<Value>(
        _ oldValue: Value?,
        _ newValue: Value?
    ) {
        guard oldValue != nil, newValue == nil else { return }
        flush()
    }

    private func flush() {
        controller.flush(request)
    }

    /// The detail and its in-place status are going away, so an edit that
    /// cannot be saved is reported to the scene instead of vanishing.
    private func reportUnsavedEditsOnLeave() {
        guard controller.flush(request) == false,
              let message = controller.unsavedChangesMessage
        else { return }
        presentationRouter.feedbackRouter.present(
            title: AppStrings.localized("task.autosave.failed"),
            message: message
        )
    }
}

extension View {
    func taskDetailAutosave(
        taskID: UUID,
        controller: TaskDetailAutosaveController,
        request: TaskDetailAutosaveRequest,
        focusedTextField: TaskEditorTextField?,
        focusedChecklistDraftID: UUID?
    ) -> some View {
        modifier(
            TaskDetailAutosaveModifier(
                taskID: taskID,
                controller: controller,
                request: request,
                focusedTextField: focusedTextField,
                focusedChecklistDraftID: focusedChecklistDraftID
            )
        )
    }

    @ViewBuilder
    fileprivate func taskDetailAutosaveTerminationFlush(
        perform action: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.willTerminateNotification
            )
        ) { _ in
            action()
        }
        #else
        self
        #endif
    }
}
