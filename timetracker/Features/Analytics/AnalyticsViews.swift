import Combine
import Foundation
import SwiftUI

struct AnalyticsView: View {
    @Environment(\.scenePhase) private var scenePhase

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
        let liveRefreshBucket = store.analyticsLiveRefreshBucket(for: evaluation)
        let request = AnalyticsSnapshotRequest(
            range: range,
            evaluation: evaluation,
            revision: store.analyticsRevision,
            liveRefreshBucket: liveRefreshBucket
        )
        let refreshPlan = scenePhase == .active
            ? AnalyticsRefreshPlan.next(
                liveNow: liveNow,
                followsCurrentPeriod: followsCurrentPeriod,
                liveRefreshBucket: liveRefreshBucket
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
        let exactCachedPresentation = store.cachedAnalyticsSnapshot(
            for: range,
            evaluation: evaluation
        ).map {
            AnalyticsLoadedSnapshot(snapshot: $0, request: request)
        }
        let displayedPresentation = exactCachedPresentation ?? loadedPresentation
        let presentationPhase = AnalyticsSnapshotPresentationPhase.resolve(
            loadedRequest: displayedPresentation?.request,
            currentRequest: request
        )

        AnalyticsContent(
            snapshot: displayedPresentation?.snapshot,
            contentIsPlaceholder: presentationPhase.obscuresLoadedMetrics,
            range: $range,
            referenceDate: effectiveReferenceDateBinding,
            liveNow: liveNow,
            monthNavigationAnchor: $monthNavigationAnchor,
            isRefreshing: presentationPhase.isRefreshing
        )
        .task(id: request) {
            guard await AnalyticsLoadUITestHook.pauseRangeReloadIfRequested(
                hasLoadedSnapshot: loadedPresentation != nil
            ) else {
                return
            }
            if let cachedSnapshot = store.cachedAnalyticsSnapshot(
                for: range,
                evaluation: evaluation
            ) {
                guard Task.isCancelled == false else { return }
                loadedPresentation = AnalyticsLoadedSnapshot(
                    snapshot: cachedSnapshot,
                    request: request
                )
                return
            }
            await Task.yield()
            guard Task.isCancelled == false else { return }
            guard let resolvedSnapshot = await store.loadAnalyticsSnapshot(
                for: range,
                evaluation: evaluation
            ) else {
                return
            }
            guard Task.isCancelled == false else { return }
            loadedPresentation = AnalyticsLoadedSnapshot(
                snapshot: resolvedSnapshot,
                request: request
            )
        }
        .task(id: refreshPlan) {
            await waitForRefresh(refreshPlan)
        }
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
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .accessibilityIdentifier("analytics.view")
            .background(AppColors.background)
            .onChange(of: range) { _, range in
                monthNavigationAnchor = nil
                guard followsCurrentPeriod == false else { return }
                let actionNow = Date()
                liveNow = actionNow
                followsCurrentPeriod = range.isCurrentPeriod(referenceDate, liveNow: actionNow)
            }
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

struct AnalyticsLoadedSnapshot {
    let snapshot: AnalyticsSnapshot
    let request: AnalyticsSnapshotRequest
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

nonisolated enum AnalyticsLoadUITestHook {
    private static let slowRangeReloadArgument = "--uitesting-slow-analytics-range-reload"

    static func pauseRangeReloadIfRequested(
        hasLoadedSnapshot: Bool,
        arguments: [String] = CommandLine.arguments
    ) async -> Bool {
        #if DEBUG
        guard hasLoadedSnapshot,
              arguments.contains("--uitesting"),
              arguments.contains(slowRangeReloadArgument)
        else {
            return Task.isCancelled == false
        }

        do {
            try await Task.sleep(for: .seconds(4))
        } catch {
            return false
        }
        return Task.isCancelled == false
        #else
        return Task.isCancelled == false
        #endif
    }
}
