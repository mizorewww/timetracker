import Combine
import Foundation
import SwiftUI

struct AnalyticsView: View {
    @Environment(\.scenePhase) private var scenePhase

    let store: TimeTrackerStore
    @State private var range: AnalyticsRange = .today
    @State private var referenceDate = Date()
    @State private var liveNow = Date()
    @State private var snapshot: AnalyticsSnapshot?
    @State private var loadedRequest: AnalyticsSnapshotRequest?
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
        let canKeepDisplayingSnapshot = loadedRequest.map {
            $0.canRemainVisible(whileLoading: request)
        } ?? false

        AnalyticsContent(
            store: store,
            snapshot: canKeepDisplayingSnapshot ? snapshot : nil,
            range: $range,
            referenceDate: effectiveReferenceDateBinding,
            liveNow: liveNow,
            monthNavigationAnchor: $monthNavigationAnchor,
            isRefreshing: loadedRequest != request
        )
        .task(id: request) {
            await Task.yield()
            guard Task.isCancelled == false else { return }
            guard let resolvedSnapshot = await store.loadAnalyticsSnapshot(
                for: range,
                evaluation: evaluation
            ) else {
                return
            }
            snapshot = resolvedSnapshot
            guard Task.isCancelled == false else { return }
            loadedRequest = request
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
