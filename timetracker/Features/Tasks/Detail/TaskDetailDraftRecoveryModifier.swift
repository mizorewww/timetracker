import SwiftUI

#if os(macOS)
import AppKit
#endif

private struct TaskDetailDraftRecoveryModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let controller: TaskDraftRecoveryController
    let sourceTaskID: UUID
    let session: TaskEditorSession
    let isReady: Bool
    @State private var persistenceTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        let request = TaskDraftRecoveryPersistenceRequest(
            isReady: isReady,
            draft: session.draft,
            hasUnsavedChanges: session.hasUnsavedChanges
        )

        content
            .task(id: isReady) {
                guard isReady else { return }
                await controller.removeExpired()
            }
            .onChange(of: request, initial: true) { _, request in
                schedulePersistence(request)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                flushCurrentDraft()
            }
            .onDisappear(perform: flushCurrentDraft)
            .taskDraftRecoveryTerminationFlush(perform: flushCurrentDraft)
    }

    private func schedulePersistence(
        _ request: TaskDraftRecoveryPersistenceRequest
    ) {
        guard request.isReady,
              let ticket = controller.makePersistenceTicket(
                  request.draft,
                  for: sourceTaskID,
                  hasUnsavedChanges: request.hasUnsavedChanges
              )
        else {
            controller.invalidatePendingPersistence(for: sourceTaskID)
            cancelPersistenceTask()
            return
        }
        let previousTask = persistenceTask
        previousTask?.cancel()
        persistenceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            await controller.persist(ticket)
        }
    }

    private func flushCurrentDraft() {
        guard isReady else {
            controller.invalidatePendingPersistence(for: sourceTaskID)
            cancelPersistenceTask()
            return
        }
        controller.flush(
            session.draft,
            for: sourceTaskID,
            hasUnsavedChanges: session.hasUnsavedChanges
        )
        cancelPersistenceTask()
    }

    private func cancelPersistenceTask() {
        persistenceTask?.cancel()
        persistenceTask = nil
    }
}

private struct TaskDraftRecoveryPersistenceRequest: Equatable {
    let isReady: Bool
    let draft: TaskEditorDraft
    let hasUnsavedChanges: Bool
}

extension View {
    func taskDetailDraftRecovery(
        controller: TaskDraftRecoveryController,
        sourceTaskID: UUID,
        session: TaskEditorSession,
        isReady: Bool
    ) -> some View {
        modifier(
            TaskDetailDraftRecoveryModifier(
                controller: controller,
                sourceTaskID: sourceTaskID,
                session: session,
                isReady: isReady
            )
        )
    }

    @ViewBuilder
    fileprivate func taskDraftRecoveryTerminationFlush(
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
