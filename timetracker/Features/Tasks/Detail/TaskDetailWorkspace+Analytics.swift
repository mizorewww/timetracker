import Foundation
import SwiftUI

enum TaskDetailAnalyticsLoadState: Equatable {
    case loading
    case content
    case empty
    case unavailable
    case failed
}

extension TaskDetailWorkspace {
    func workspace(for task: TaskNode) -> some View {
        TaskDetailAnalyticsWorkspace(
            store: store,
            task: task,
            session: session,
            autosaveController: autosaveController,
            focusedTextField: $focusedTextField,
            focusedChecklistDraftID: $focusedChecklistDraftID
        )
    }
}

private struct TaskDetailAnalyticsWorkspace: View {
    @Environment(\.scenePhase) private var scenePhase

    let store: TimeTrackerStore
    let task: TaskNode
    let session: TaskEditorSession
    let autosaveController: TaskDetailAutosaveController
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    let focusedChecklistDraftID: FocusState<UUID?>.Binding

    @State private var range: AnalyticsRange = .week
    @State private var referenceDate = Date()
    @State private var liveNow = Date()
    @State private var followsCurrentPeriod = true
    @State private var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?
    @State private var snapshot: TaskAnalyticsSnapshot?
    @State private var loadedRequest: TaskAnalyticsSnapshotRequest?
    @State private var loadState: TaskDetailAnalyticsLoadState = .loading
    @State private var retryID = UUID()
    @State private var authorizationRetryID: UUID?
    @State private var activeLoadID: UUID?

    var body: some View {
        let evaluationDate = liveNow
        let effectiveReferenceDate = followsCurrentPeriod
            ? evaluationDate
            : referenceDate
        let request = store.taskAnalyticsSnapshotRequest(
            for: task,
            range: range,
            referenceDate: effectiveReferenceDate,
            liveNow: evaluationDate
        )
        let loadRequest = TaskDetailAnalyticsLoadRequest(
            request: request,
            retryID: retryID
        )
        let refreshPlan = scenePhase == .active
            ? AnalyticsRefreshPlan.next(
                liveNow: evaluationDate,
                followsCurrentPeriod: followsCurrentPeriod,
                liveRefreshBucket: request.liveRefreshBucket
            )
            : nil
        let canKeepDisplayingSnapshot = loadedRequest.map {
            $0.canRemainVisible(whileLoading: request)
        } ?? false
        let visibleSnapshot = loadedRequest == request || canKeepDisplayingSnapshot
            ? snapshot
            : nil

        TaskDetailList(
            store: store,
            task: task,
            session: session,
            autosaveController: autosaveController,
            focusedTextField: focusedTextField,
            focusedChecklistDraftID: focusedChecklistDraftID,
            snapshot: visibleSnapshot,
            analyticsState: loadState,
            isAppleHealthTask: isAppleHealthTask,
            range: rangeSelection,
            referenceDate: referenceDateSelection,
            liveNow: evaluationDate,
            monthNavigationAnchor: $monthNavigationAnchor,
            isRefreshing: loadState == .loading && visibleSnapshot != nil,
            retryAnalytics: retry
        )
        .task(id: loadRequest) {
            await loadSnapshot(
                for: request,
                loadRequest: loadRequest,
                evaluationDate: evaluationDate
            )
        }
        .task(id: refreshPlan) {
            await waitForRefresh(refreshPlan)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            liveNow = Date()
            refreshAfterSceneActivation()
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

    private var isAppleHealthTask: Bool {
        AppleHealthTaskCatalog.taskRole(for: task.id) != nil
    }

    private var rangeSelection: Binding<AnalyticsRange> {
        Binding(
            get: { range },
            set: selectRange
        )
    }

    private var referenceDateSelection: Binding<Date> {
        Binding(
            get: { followsCurrentPeriod ? liveNow : referenceDate },
            set: selectReferenceDate
        )
    }

    private func selectRange(_ selectedRange: AnalyticsRange) {
        guard selectedRange != range else { return }
        let evaluationDate = Date()
        let selectedReferenceDate = followsCurrentPeriod
            ? evaluationDate
            : referenceDate
        let followsSelectedPeriod = selectedRange.isCurrentPeriod(
            selectedReferenceDate,
            liveNow: evaluationDate
        )
        let effectiveReferenceDate = followsSelectedPeriod
            ? evaluationDate
            : selectedReferenceDate
        let request = store.taskAnalyticsSnapshotRequest(
            for: task,
            range: selectedRange,
            referenceDate: effectiveReferenceDate,
            liveNow: evaluationDate
        )

        if isAppleHealthTask == false,
           let resolvedSnapshot = store.taskAnalyticsSnapshot(
               for: request,
               now: evaluationDate
           )
        {
            // Keep the existing tracked-task transition atomic. Apple Health
            // evidence stays on the cancellable asynchronous path below.
            snapshot = resolvedSnapshot
            loadedRequest = request
            loadState = .content
        }
        range = selectedRange
        referenceDate = selectedReferenceDate
        followsCurrentPeriod = followsSelectedPeriod
        monthNavigationAnchor = nil
        liveNow = evaluationDate
    }

    private func selectReferenceDate(_ selectedDate: Date) {
        let actionNow = Date()
        let boundedDate = min(selectedDate, actionNow)
        referenceDate = boundedDate
        liveNow = actionNow
        followsCurrentPeriod = range.isCurrentPeriod(
            boundedDate,
            liveNow: actionNow
        )
    }

    private func retry() {
        let newRetryID = UUID()
        authorizationRetryID = newRetryID
        retryID = newRetryID
    }

    private func refreshAfterSceneActivation() {
        guard isAppleHealthTask, loadedRequest != nil else { return }
        // Returning from Settings or Health can change readable evidence even
        // when the selected day/week/month request identity is unchanged.
        // Refresh without presenting the authorization sheet automatically.
        authorizationRetryID = nil
        retryID = UUID()
    }

    @MainActor
    private func loadSnapshot(
        for request: TaskAnalyticsSnapshotRequest,
        loadRequest: TaskDetailAnalyticsLoadRequest,
        evaluationDate: Date
    ) async {
        let loadID = UUID()
        activeLoadID = loadID

        let canKeepDisplayingSnapshot = loadedRequest.map {
            $0.canRemainVisible(whileLoading: request)
        } ?? false
        if canKeepDisplayingSnapshot == false, loadedRequest != request {
            snapshot = nil
        }
        loadState = .loading

        let allowsAuthorizationRequest = loadedRequest == nil
            || authorizationRetryID == loadRequest.retryID
        if authorizationRetryID == loadRequest.retryID {
            authorizationRetryID = nil
        }

        do {
            let resolvedSnapshot = try await store.loadTaskAnalyticsSnapshot(
                for: request,
                now: evaluationDate,
                calendar: .current,
                allowsAuthorizationRequest: allowsAuthorizationRequest
            )
            guard Task.isCancelled == false,
                  activeLoadID == loadID,
                  currentLoadRequest == loadRequest
            else {
                return
            }

            loadedRequest = request
            snapshot = resolvedSnapshot
            guard let resolvedSnapshot else {
                loadState = .failed
                return
            }
            loadState = resolvedSnapshot.source == .appleHealth
                && resolvedSnapshot.overview.grossSeconds == 0
                && resolvedSnapshot.recentRecords.isEmpty
                ? .empty
                : .content
        } catch is CancellationError {
            return
        } catch let error as AppleHealthReadError where error == .unavailable {
            guard Task.isCancelled == false,
                  activeLoadID == loadID,
                  currentLoadRequest == loadRequest
            else {
                return
            }
            loadedRequest = request
            snapshot = canKeepDisplayingSnapshot ? snapshot : nil
            loadState = .unavailable
        } catch {
            guard Task.isCancelled == false,
                  activeLoadID == loadID,
                  currentLoadRequest == loadRequest
            else {
                return
            }
            loadedRequest = request
            snapshot = canKeepDisplayingSnapshot ? snapshot : nil
            loadState = .failed
        }
    }

    private var currentLoadRequest: TaskDetailAnalyticsLoadRequest {
        let effectiveReferenceDate = followsCurrentPeriod
            ? liveNow
            : referenceDate
        return TaskDetailAnalyticsLoadRequest(
            request: store.taskAnalyticsSnapshotRequest(
                for: task,
                range: range,
                referenceDate: effectiveReferenceDate,
                liveNow: liveNow
            ),
            retryID: retryID
        )
    }

    @MainActor
    private func waitForRefresh(_ plan: AnalyticsRefreshPlan?) async {
        guard let plan else { return }
        let delay = max(0, plan.deadline.timeIntervalSinceNow)
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return
        }
        guard Task.isCancelled == false else { return }
        liveNow = Date()
    }
}

private struct TaskDetailAnalyticsLoadRequest: Hashable {
    let request: TaskAnalyticsSnapshotRequest
    let retryID: UUID
}
