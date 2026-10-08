import SwiftUI

#if os(macOS)
import AppKit
#endif

private struct TaskDetailAutosaveModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let controller: TaskDetailAutosaveController
    let recoveryController: TaskDraftRecoveryController
    let sourceTaskID: UUID
    let request: TaskDetailAutosaveRequest
    let focusedTextField: TaskEditorTextField?
    let focusedChecklistDraftID: UUID?
    @State private var recoveryPersistenceTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: request, initial: true) { _, request in
                controller.update(with: request)
                scheduleRecoveryPersistence(request)
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
            .onDisappear(perform: flush)
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
        recoveryPersistenceTask?.cancel()
        recoveryPersistenceTask = nil
        guard request.isEnabled else { return }
        let draft = request.draft
        let hasUnsavedChanges = request.hasUnsavedChanges
        Task {
            await recoveryController.persist(
                draft,
                for: sourceTaskID,
                hasUnsavedChanges: hasUnsavedChanges
            )
        }
    }

    /// Mirrors the current unsaved draft so a relaunch can restore it. Runs off
    /// the type path: the recovery store only ever holds unsaved edits.
    private func scheduleRecoveryPersistence(
        _ request: TaskDetailAutosaveRequest
    ) {
        recoveryPersistenceTask?.cancel()
        recoveryPersistenceTask = nil
        guard request.isEnabled else { return }
        let draft = request.draft
        let hasUnsavedChanges = request.hasUnsavedChanges
        recoveryPersistenceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            await recoveryController.persist(
                draft,
                for: sourceTaskID,
                hasUnsavedChanges: hasUnsavedChanges
            )
        }
    }
}

extension View {
    func taskDetailAutosave(
        controller: TaskDetailAutosaveController,
        recoveryController: TaskDraftRecoveryController,
        sourceTaskID: UUID,
        request: TaskDetailAutosaveRequest,
        focusedTextField: TaskEditorTextField?,
        focusedChecklistDraftID: UUID?
    ) -> some View {
        modifier(
            TaskDetailAutosaveModifier(
                controller: controller,
                recoveryController: recoveryController,
                sourceTaskID: sourceTaskID,
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
