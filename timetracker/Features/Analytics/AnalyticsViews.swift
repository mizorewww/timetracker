import Combine
import Foundation
import SwiftUI

struct AnalyticsView: View {
    let store: TimeTrackerStore
    @State private var range: AnalyticsRange = .today
    @State private var referenceDate = Date()
    @State private var liveNow = Date()
    @State private var loadedPresentation: AnalyticsLoadedSnapshot?
    @State private var followsCurrentPeriod = true
    @State private var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?

    var body: some View {
        let effectiveReferenceDate = followsCurrentPeriod ? liveNow : referenceDate
        let evaluation = range.evaluation(
            referenceDate: effectiveReferenceDate,
            liveNow: liveNow
        )
        let presentation = AnalyticsSnapshotPresentation(
            store: store,
            range: range,
            evaluation: evaluation,
            loaded: loadedPresentation
        )
        let clockDeadline = followsCurrentPeriod
            ? LiveClockDeadline.next(
                after: liveNow,
                isLive: presentation.request.evaluationKey.liveRefreshBucket != nil
            )
            : nil
        let effectiveReferenceDateBinding = Binding(
            get: { followsCurrentPeriod ? liveNow : referenceDate },
            set: { newDate in
                let actionNow = Date()
                liveNow = actionNow
                referenceDate = newDate
                followsCurrentPeriod = range.isCurrentPeriod(newDate, liveNow: actionNow)
            }
        )
        AnalyticsContent(
            snapshot: presentation.displayed?.snapshot,
            contentIsPlaceholder: presentation.phase.obscuresLoadedMetrics,
            range: $range,
            referenceDate: effectiveReferenceDateBinding,
            liveNow: liveNow,
            monthNavigationAnchor: $monthNavigationAnchor,
            isRefreshing: presentation.phase.isRefreshing
        )
        .task(id: presentation.request) {
            guard let loaded = await presentation.load(
                store: store,
                range: range,
                evaluation: evaluation
            ) else { return }
            loadedPresentation = loaded
        }
        .liveClock($liveNow, until: clockDeadline)
        .navigationDestination(for: AnalyticsCategory.self) { category in
            AnalyticsCategoryDetailView(
                store: store,
                category: category,
                range: $range,
                referenceDate: effectiveReferenceDateBinding,
                liveNow: liveNow,
                monthNavigationAnchor: $monthNavigationAnchor
            )
        }
        .navigationDestination(for: AnalyticsStandalonePage.self) { page in
            switch page {
            case .heatmaps:
                AnalyticsHeatmapView(store: store)
            }
        }
        .navigationTitle(AppStrings.analytics)
        .appInlineNavigationTitle()
        .accessibilityIdentifier("analytics.view")
        .background(AppColors.background)
        .onChange(of: range) { _, range in
            monthNavigationAnchor = nil
            guard followsCurrentPeriod == false else { return }
            let actionNow = Date()
            liveNow = actionNow
            followsCurrentPeriod = range.isCurrentPeriod(referenceDate, liveNow: actionNow)
        }
    }
}

struct AnalyticsLoadedSnapshot {
    let snapshot: AnalyticsSnapshot
    let request: AnalyticsSnapshotRequest
}

/// What an analytics page shows for its selected period: the store's exact
/// cached snapshot when there is one, else the last one the page loaded, and
/// how that relates to the current request. Shared by the analytics home and
/// category detail pages.
@MainActor
struct AnalyticsSnapshotPresentation {
    let request: AnalyticsSnapshotRequest
    let displayed: AnalyticsLoadedSnapshot?
    let phase: AnalyticsSnapshotPresentationPhase

    init(
        store: TimeTrackerStore,
        range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        loaded: AnalyticsLoadedSnapshot?
    ) {
        let request = AnalyticsSnapshotRequest(
            range: range,
            evaluation: evaluation,
            revision: store.analyticsRevision,
            liveRefreshBucket: store.analyticsLiveRefreshBucket(for: evaluation)
        )
        let cached = store.cachedAnalyticsSnapshot(for: range, evaluation: evaluation)
            .map { AnalyticsLoadedSnapshot(snapshot: $0, request: request) }
        self.request = request
        displayed = cached ?? loaded
        phase = AnalyticsSnapshotPresentationPhase.resolve(
            loadedRequest: displayed?.request,
            currentRequest: request
        )
    }

    /// The snapshot for `request`, or nil when the load was cancelled.
    func load(
        store: TimeTrackerStore,
        range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation
    ) async -> AnalyticsLoadedSnapshot? {
        if let cached = store.cachedAnalyticsSnapshot(for: range, evaluation: evaluation) {
            return Task.isCancelled ? nil : AnalyticsLoadedSnapshot(snapshot: cached, request: request)
        }
        // Aggregation runs on the main actor; let the loading state render first.
        await Task.yield()
        guard Task.isCancelled == false,
              let snapshot = await store.loadAnalyticsSnapshot(for: range, evaluation: evaluation),
              Task.isCancelled == false
        else { return nil }
        return AnalyticsLoadedSnapshot(snapshot: snapshot, request: request)
    }
}

nonisolated enum AnalyticsSnapshotPresentationPhase: Equatable, Sendable {
    case initialLoading
    case loadingNewPeriod
    case refreshingVisiblePeriod
    case current

    static func resolve(
        loadedRequest: AnalyticsSnapshotRequest?,
        currentRequest: AnalyticsSnapshotRequest
    ) -> Self {
        guard let loadedRequest else { return .initialLoading }
        guard loadedRequest != currentRequest else { return .current }
        if loadedRequest.canRemainVisible(whileLoading: currentRequest) {
            return .refreshingVisiblePeriod
        }
        return .loadingNewPeriod
    }

    var isRefreshing: Bool {
        self != .current
    }

    var obscuresLoadedMetrics: Bool {
        self == .loadingNewPeriod
    }
}
