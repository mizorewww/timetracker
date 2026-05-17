import Combine
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var store: TimeTrackerStore
    var isActive = true
    @State private var range: AnalyticsRange = .today
    @State private var referenceDate = Date()
    @State private var now = Date()
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    private let analyticsRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var isCompactPhone: Bool {
        #if os(iOS)
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
        #else
        false
        #endif
    }

    var body: some View {
        let request = snapshotRequest
        AnalyticsContent(
            store: store,
            snapshot: store.displayAnalyticsSnapshot(for: request),
            range: $range,
            referenceDate: $referenceDate,
            now: now,
            isCompactPhone: isCompactPhone
        )
        .navigationTitle(AppStrings.analytics)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .phoneRootChrome(destination: .analytics, enabled: isCompactPhone)
        #endif
        .background(AppColors.background)
        .task(id: request) {
            refreshSnapshot(for: request)
        }
        .onChange(of: isActive) { _, active in
            guard active else { return }
            refreshSnapshot(for: snapshotRequest)
        }
        .onReceive(analyticsRefreshTimer) { date in
            guard isActive else { return }
            now = date
            if referenceDate > date {
                referenceDate = date
            }
        }
    }

    private var snapshotRequest: AnalyticsSnapshotRequest {
        AnalyticsSnapshotRequest(
            range: range,
            snapshotDate: range.effectiveSnapshotDate(referenceDate: referenceDate, liveNow: now)
        )
    }

    private func refreshSnapshot(for request: AnalyticsSnapshotRequest) {
        guard isActive else { return }
        store.refreshAnalyticsSnapshot(for: request.range, now: request.snapshotDate)
    }
}

private struct AnalyticsContent: View {
    @ObservedObject var store: TimeTrackerStore
    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let now: Date
    let isCompactPhone: Bool

    var body: some View {
        List {
            #if os(iOS)
            if isCompactPhone {
                PhoneLargePageHeader(destination: .analytics)
                    .listRowInsets(PhoneRootChromeMetrics.groupedHeaderRowInsets)
                    .listRowBackground(Color.clear)
            }
            #endif

            Section {
                AnalyticsHomeSummaryRow(snapshot: snapshot)
            } header: {
                Text(AppStrings.localized("analytics.summary.title"))
            } footer: {
                Text(String(format: AppStrings.localized("analytics.summary.periodFootnote"), AnalyticsPeriodText.title(for: range, date: referenceDate)))
            }

            Section {
                ForEach(AnalyticsCategory.allCases) { category in
                    NavigationLink {
                        AnalyticsCategoryDetailView(
                            store: store,
                            category: category,
                            range: $range,
                            referenceDate: $referenceDate,
                            now: now
                        )
                        #if os(iOS)
                        .phoneSecondaryDestination(.analytics, enabled: isCompactPhone)
                        #endif
                    } label: {
                        AnalyticsCategoryRow(category: category, snapshot: snapshot)
                    }
                }
            } header: {
                Text(AppStrings.localized("analytics.categories.title"))
            } footer: {
                Text(AppStrings.localized("analytics.categories.footer"))
            }

            #if os(iOS)
            if isCompactPhone {
                PhoneRootListBottomClearanceRow()
            }
            #endif
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .phoneRootScrollMargins(enabled: isCompactPhone)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .phoneChromeScrollObserver(destination: .analytics, enabled: isCompactPhone)
        #endif
        .background(AppColors.background)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
