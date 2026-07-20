import Combine
import Foundation
import SwiftUI
struct TaskDetailWorkspace: View {
    @Environment(\.scenePhase) private var scenePhase
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
        _session = State(
            initialValue: TaskEditorSession(
                store: store,
                initialDraft: initialDraft
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
        .taskDetailDraftRecovery(
            controller: store.taskDraftRecoveryController,
            sourceTaskID: taskID,
            session: session,
            isReady: draftRecoveryLoadState == .ready
        )
        .onChange(of: editorSourceToken) {
            session.synchronizeWithStoreIfClean(taskID: taskID)
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

    private func workspace(for task: TaskNode) -> some View {
        let evaluationDate = liveNow
        let request = store.taskAnalyticsSnapshotRequest(
            for: task,
            range: range,
            now: evaluationDate
        )
        let refreshPlan = scenePhase == .active
            ? AnalyticsRefreshPlan.next(
                liveNow: evaluationDate,
                followsCurrentPeriod: true,
                liveRefreshBucket: request.liveRefreshBucket
            )
            : nil
        let canKeepDisplayingSnapshot = loadedRequest.map {
            $0.canRemainVisible(whileLoading: request)
        } ?? false

        return TaskDetailList(
            store: store,
            task: task,
            session: session,
            focusedTextField: $focusedTextField,
            focusedChecklistDraftID: $focusedChecklistDraftID,
            snapshot: canKeepDisplayingSnapshot ? snapshot : nil,
            range: rangeSelection(for: task),
            isRefreshing: canKeepDisplayingSnapshot && loadedRequest != request
        )
        .task(id: request) {
            guard loadedRequest != request || snapshot == nil else { return }
            snapshot = store.taskAnalyticsSnapshot(for: request, now: evaluationDate)
            loadedRequest = request
        }
        .task(id: refreshPlan) {
            await waitForRefresh(refreshPlan)
        }
    }
    private func rangeSelection(for task: TaskNode) -> Binding<AnalyticsRange> {
        Binding(
            get: { range },
            set: { selectRange($0, for: task) }
        )
    }

}

enum TaskDraftRecoveryLoadState: Equatable {
    case loading
    case ready
    case failed
}
