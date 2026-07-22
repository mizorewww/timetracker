import SwiftUI

struct HomeInformationItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let body: String
}

struct HomeSectionInformationButton: View {
    let title: String
    let buttonIdentifier: String
    let viewIdentifier: String
    let items: [HomeInformationItem]

    var body: some View {
        InformationPresentationButton(
            title: String.localizedStringWithFormat(
                AppStrings.localized("home.info.format"),
                title
            ),
            accessibilityIdentifier: buttonIdentifier
        ) {
            HomeSectionInformationView(
                title: title,
                viewIdentifier: viewIdentifier,
                items: items
            )
            .frame(
                minWidth: 320,
                idealWidth: 420,
                maxWidth: 520,
                minHeight: 280
            )
        }
    }
}

extension HomeSectionInformationButton {
    static func overview(
        showsWallTime: Bool
    ) -> HomeSectionInformationButton {
        HomeSectionInformationButton(
            title: AppStrings.localized("home.overview.title"),
            buttonIdentifier: "home.overview.info",
            viewIdentifier: "home.info.overview",
            items: [
                HomeInformationItem(
                    id: "home.info.overview.summary",
                    icon: "rectangle.grid.2x2",
                    title: AppStrings.localized("home.overview.title"),
                    body: AppStrings.localized("home.subtitle")
                ),
                HomeInformationItem(
                    id: "home.info.overview.gross",
                    icon: "square.stack.3d.up",
                    title: AppStrings.grossTime,
                    body: AppStrings.localized("analytics.glossary.gross")
                )
            ] + (showsWallTime ? [
                HomeInformationItem(
                    id: "home.info.overview.wall",
                    icon: "timeline.selection",
                    title: AppStrings.wallTime,
                    body: AppStrings.localized("analytics.glossary.wall")
                )
            ] : [])
        )
    }

    static var weeklyGross: HomeSectionInformationButton {
        HomeSectionInformationButton(
            title: AppStrings.localized("home.weeklyGross.title"),
            buttonIdentifier: "home.weeklyGross.info",
            viewIdentifier: "home.info.weeklyGross",
            items: [
                HomeInformationItem(
                    id: "home.info.weeklyGross.summary",
                    icon: "chart.bar.xaxis",
                    title: AppStrings.localized("home.weeklyGross.title"),
                    body: AppStrings.localized("home.weeklyGross.footer")
                )
            ]
        )
    }

    static func heatmaps(
        snapshots: [TaskActivityHeatmapSnapshot],
        locale: Locale
    ) -> HomeSectionInformationButton {
        HomeSectionInformationButton(
            title: AppStrings.localized("home.heatmap.title"),
            buttonIdentifier: "home.heatmaps.info",
            viewIdentifier: "home.info.heatmaps",
            items: [
                HomeInformationItem(
                    id: "home.info.heatmaps.summary",
                    icon: "square.grid.3x3.fill",
                    title: AppStrings.localized("home.heatmap.title"),
                    body: AppStrings.localized("home.heatmap.section.footer")
                ),
                HomeInformationItem(
                    id: "home.info.heatmaps.duration",
                    icon: "timer",
                    title: AppStrings.localized("home.heatmap.metric.duration"),
                    body: AppStrings.localized("home.heatmap.info.duration")
                ),
                HomeInformationItem(
                    id: "home.info.heatmaps.checklist",
                    icon: "checklist",
                    title: AppStrings.localized("home.heatmap.metric.checklist"),
                    body: AppStrings.localized("home.heatmap.info.checklist")
                ),
                HomeInformationItem(
                    id: "home.info.heatmaps.quantity",
                    icon: "number",
                    title: AppStrings.localized("home.heatmap.info.quantity.title"),
                    body: AppStrings.localized("home.heatmap.info.quantity")
                )
            ] + snapshots.map { snapshot in
                HomeInformationItem(
                    id: "home.info.heatmaps.task.\(snapshot.taskID.uuidString)",
                    icon: snapshot.iconName,
                    title: snapshot.title,
                    body: heatmapExplanation(
                        for: snapshot,
                        locale: locale
                    )
                )
            }
        )
    }

    private static func heatmapExplanation(
        for snapshot: TaskActivityHeatmapSnapshot,
        locale: Locale
    ) -> String {
        let maximum = ActivityHeatmapValueFormatter.compact(
            snapshot.maximumDailyValue,
            metric: snapshot.metric,
            locale: locale
        )
        let key: String
        switch snapshot.metric {
        case .trackedDuration:
            key = "home.heatmap.footer.durationFormat"
        case .checklistCompletions:
            key = "home.heatmap.footer.checklistFormat"
        case .quantity:
            key = "home.heatmap.footer.quantityFormat"
        }
        return String.localizedStringWithFormat(
            AppStrings.localized(key),
            maximum
        )
    }

    static var quickStart: HomeSectionInformationButton {
        HomeSectionInformationButton(
            title: AppStrings.quickStart,
            buttonIdentifier: "home.quickStart.info",
            viewIdentifier: "home.info.quickStart",
            items: [
                HomeInformationItem(
                    id: "home.info.quickStart.summary",
                    icon: "bolt.fill",
                    title: AppStrings.quickStart,
                    body: AppStrings.localized("quickStart.defaultHint")
                )
            ]
        )
    }
}

private struct HomeSectionInformationView: View {
    let title: String
    let viewIdentifier: String
    let items: [HomeInformationItem]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items) { item in
                InformationGuideRow(
                    icon: item.icon,
                    title: item.title,
                    bodyText: item.body
                )
                .accessibilityIdentifier(item.id)
            }
            .accessibilityIdentifier(viewIdentifier)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.done) {
                        dismiss()
                    }
                    .accessibilityIdentifier("home.info.done")
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }
}
