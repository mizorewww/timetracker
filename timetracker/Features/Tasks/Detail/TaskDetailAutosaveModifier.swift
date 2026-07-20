import SwiftUI

#if os(macOS)
import AppKit
#endif

private struct TaskDetailAutosaveModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

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
                controller.flush(request)
            }
            .onDisappear {
                controller.flush(request)
            }
            .taskDetailAutosaveTerminationFlush {
                controller.flush(request)
            }
    }

    private func flushWhenFocusLeaves<Value>(
        _ oldValue: Value?,
        _ newValue: Value?
    ) {
        guard oldValue != nil, newValue == nil else { return }
        controller.flush(request)
    }
}

extension View {
    func taskDetailAutosave(
        controller: TaskDetailAutosaveController,
        request: TaskDetailAutosaveRequest,
        focusedTextField: TaskEditorTextField?,
        focusedChecklistDraftID: UUID?
    ) -> some View {
        modifier(
            TaskDetailAutosaveModifier(
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
