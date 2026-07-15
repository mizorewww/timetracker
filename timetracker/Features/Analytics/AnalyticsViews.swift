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

        Group {
            if let snapshot, loadedRequest == request {
                AnalyticsContent(
                    snapshot: snapshot,
                    range: $range,
                    referenceDate: effectiveReferenceDateBinding,
                    liveNow: liveNow
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(AppStrings.localized("analytics.loading"))
            }
        }
        .task(id: request) {
            snapshot = store.analyticsSnapshot(for: range, evaluation: evaluation)
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
                liveNow: liveNow
            )
        }
        .navigationTitle(AppStrings.analytics)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("analytics.view")
        .background(AppColors.background)
        .onChange(of: range) { _, range in
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

private struct AnalyticsContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date

    var body: some View {
        List {
            AnalyticsPeriodSection(range: $range, referenceDate: $referenceDate, liveNow: liveNow)

            Section {
                AnalyticsHomeSummaryRow(snapshot: snapshot)
            } header: {
                Text(AppStrings.localized("analytics.summary.title"))
            } footer: {
                Text(
                    String(
                        format: AppStrings.localized("analytics.summary.periodFootnote"),
                        AnalyticsPeriodText.title(
                            for: range,
                            date: referenceDate,
                            liveNow: liveNow
                        )
                    )
                )
            }

            Section {
                categoryLinks(AnalyticsCategory.reviewCategories)
            } header: {
                Text(AppStrings.localized("analytics.review.title"))
            }

            Section {
                categoryLinks(AnalyticsCategory.exploreCategories)
            } header: {
                Text(AppStrings.localized("analytics.categories.title"))
            } footer: {
                Text(AppStrings.localized("analytics.categories.footer"))
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .contentMargins(
            .bottom,
            dynamicTypeSize.isAccessibilitySize ? 112 : 16,
            for: .scrollContent
        )
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .accessibilityIdentifier("analytics.view")
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private func categoryLinks(_ categories: [AnalyticsCategory]) -> some View {
        ForEach(categories) { category in
            NavigationLink(value: category) {
                AnalyticsCategoryRow(category: category, snapshot: snapshot)
            }
            .accessibilityIdentifier("analytics.category.\(category.rawValue)")
        }
    }
}
