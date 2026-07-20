import Combine
import Foundation
import SwiftUI
struct TaskDetailWorkspace: View {
    @Environment(\.scenePhase) var scenePhase
    let store: TimeTrackerStore
    let taskID: UUID
    let returnDestination: TimeTrackerStore.DesktopDestination
    let dismissDetail: () -> Void
    let replaceDetail: (UUID) -> Void
    @State var range: AnalyticsRange = .week
    @State var liveNow = Date()
    @State var snapshot: TaskAnalyticsSnapshot?
    @State var loadedRequest: TaskAnalyticsSnapshotRequest?
    @State var session: TaskEditorSession
    @State var autosaveController: TaskDetailAutosaveController
    @State var navigationGuardRegistration = TaskDetailNavigationRegistrationToken()
    @State var draftRecoveryReason: TaskDraftRecoveryReason?
    @State var savedRecoveryCopyTaskID: UUID?
    @State var isFinishingRecoveryCleanup = false
    @State var isCompletingRecoveryNavigation = false
    @State var draftRecoveryLoadState: TaskDraftRecoveryLoadState = .loading
    @State var draftRecoveryLoadRequestID = UUID()
    @FocusState var focusedTextField: TaskEditorTextField?
    @FocusState var focusedChecklistDraftID: UUID?
    init(
        store: TimeTrackerStore,
        taskID: UUID,
        initialDraft: TaskEditorDraft,
        returnDestination: TimeTrackerStore.DesktopDestination,
        dismissDetail: @escaping () -> Void,
        replaceDetail: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.taskID = taskID
        self.returnDestination = returnDestination
        self.dismissDetail = dismissDetail
        self.replaceDetail = replaceDetail
        let session = TaskEditorSession(store: store, initialDraft: initialDraft)
        _session = State(initialValue: session)
        _autosaveController = State(
            initialValue: .workspaceController(
                store: store,
                session: session,
                taskID: taskID,
                returnDestination: returnDestination
            )
        )
    }
    var body: some View {
        Group {
            switch draftRecoveryLoadState {
            case .loading:
                TaskDetailDraftRecoveryLoadingView()
            case .failed:
                TaskDetailDraftRecoveryLoadFailureView(
                    retry: retryDraftRecoveryLoad
                )
            case .ready where isPresentingRecovery:
                TaskDetailRecoveryList(
                    store: store,
                    session: session,
                    reason: activeDraftRecoveryReason ?? .sourceUnavailable,
                    isAwaitingCleanup: savedRecoveryCopyTaskID != nil,
                    isFinishingCleanup: isFinishingRecoveryCleanup,
                    focusedTextField: $focusedTextField,
                    focusedChecklistDraftID: $focusedChecklistDraftID,
                    saveAsNew: savePreservedDraftAsNew,
                    restoreOriginal: restoreArchivedSource,
                    leaveCleanup: leaveRecoveryCleanup,
                    discard: requestDiscard
                )
            case .ready:
                if let task = store.task(for: taskID) {
                    workspace(for: task)
                }
            }
        }
        .taskDetailNavigation(
            store: store,
            taskID: taskID,
            session: session,
            isSourceUnavailable: isPresentingRecovery,
            isAwaitingRecoveryCleanup: savedRecoveryCopyTaskID != nil,
            save: save,
            requestDiscard: requestDiscard,
            preservingDestination: returnDestination
        )
        .taskEditorSessionSafety(
            session: session,
            discard: discardChanges,
            reload: reloadLatestDraft
        )
        .taskDetailAutosave(
            controller: autosaveController,
            request: autosaveRequest,
            focusedTextField: focusedTextField,
            focusedChecklistDraftID: focusedChecklistDraftID
        )
        .taskDetailDraftRecovery(
            controller: store.taskDraftRecoveryController,
            sourceTaskID: taskID,
            session: session,
            isReady: draftRecoveryLoadState == .ready
        )
        .onChange(of: editorSourceToken) { _, sourceToken in
            guard let sourceToken else { return }
            session.synchronizeWithStoreIfClean(
                taskID: taskID,
                sourceBaseline: sourceToken.baseline,
                parentCandidateIDs: sourceToken.parentCandidateIDs
            )
        }
        .onChange(of: session.isDiscardConfirmationPresented) { _, isPresented in
            cancelPendingNavigationIfNeeded(
                isDiscardConfirmationPresented: isPresented
            )
        }
        .onChange(
            of: session.hasUnsavedChanges,
            updateNavigationGuardForDraftChanges
        )
        .onChange(of: autosaveController.status, handleAutosaveStatus)
        .task(id: isSourceUnavailable) {
            prepareRecoveryIfNeeded()
        }
        .task(id: draftRecoveryLoadRequestID) {
            await loadPersistedDraftRecovery()
        }
        .onAppear(perform: registerNavigationGuard)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            liveNow = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            liveNow = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            liveNow = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            liveNow = Date()
        }
    }

}

enum TaskDraftRecoveryLoadState: Equatable {
    case loading
    case ready
    case failed
}
