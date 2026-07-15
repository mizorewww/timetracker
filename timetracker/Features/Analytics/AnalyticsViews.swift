import SwiftUI

struct AnalyticsView: View {
    let store: TimeTrackerStore
    @State private var range: AnalyticsRange = .today
    @State private var referenceDate = Date()
    @State private var snapshot: AnalyticsSnapshot?
    @State private var loadedRequest: AnalyticsSnapshotRequest?
    @State private var followsCurrentPeriod = true
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let effectiveReferenceDate = followsCurrentPeriod ? context.date : referenceDate
            let snapshotDate = range.effectiveSnapshotDate(referenceDate: effectiveReferenceDate, liveNow: context.date)
            let request = AnalyticsSnapshotRequest(range: range, referenceDate: effectiveReferenceDate,
                revision: store.analyticsRevision, liveRefreshBucket: store.analyticsLiveRefreshBucket(for: range, now: snapshotDate))
            let effectiveReferenceDateBinding = Binding(
                get: { followsCurrentPeriod ? context.date : referenceDate },
                set: { newDate in
                    referenceDate = newDate
                    followsCurrentPeriod = range.isCurrentPeriod(newDate, liveNow: context.date)
                }
            )
            Group {
                if let snapshot, loadedRequest == request {
                    AnalyticsContent(
                        snapshot: snapshot,
                        range: $range,
                        referenceDate: effectiveReferenceDateBinding,
                        liveNow: context.date
                    )
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(AppStrings.localized("analytics.loading"))
                }
            }
            .task(id: request) {
                snapshot = store.analyticsSnapshot(for: range, now: snapshotDate)
                loadedRequest = request
            }
            .navigationDestination(for: AnalyticsCategory.self) { category in
                AnalyticsCategoryDetailView(
                    store: store,
                    category: category,
                    range: $range,
                    referenceDate: effectiveReferenceDateBinding
                )
            }
        }
        .navigationTitle(AppStrings.analytics)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("analytics.view")
        .background(AppColors.background)
        .onChange(of: range) { _, range in
            guard followsCurrentPeriod == false else { return }
            followsCurrentPeriod = range.isCurrentPeriod(referenceDate, liveNow: Date())
        }
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
                        AnalyticsPeriodText.title(for: range, date: referenceDate)
                    )
                )
            }

            Section {
                ForEach(AnalyticsCategory.allCases) { category in
                    NavigationLink(value: category) {
                        AnalyticsCategoryRow(category: category, snapshot: snapshot)
                    }
                }
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
}
