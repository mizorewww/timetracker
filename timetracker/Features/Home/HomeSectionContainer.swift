import SwiftUI

enum HomeSectionContainer {
    case card
    case listSection
}

struct HomeSectionHeader<Trailing: View>: View {
    let container: HomeSectionContainer
    let title: String
    let summary: String?
    let accessibilityIdentifier: String
    private let trailing: Trailing

    init(
        container: HomeSectionContainer,
        title: String,
        summary: String? = nil,
        accessibilityIdentifier: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.container = container
        self.title = title
        self.summary = summary
        self.accessibilityIdentifier = accessibilityIdentifier
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                titleView
                Spacer(minLength: 8)
                if let summary {
                    Text(summary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(accessibilityIdentifier)

            trailing
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch container {
        case .card:
            Text(title)
                .font(.headline)
        case .listSection:
            Text(title)
        }
    }
}

extension View {
    func homeVisualizationListSection() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Draws a card that matches the native inset-grouped card look
    /// (large continuous corners, grouped background, no stroke) while
    /// keeping every visualization in its own card. Consecutive grouped
    /// `Section`s merge into one continuous card on iOS 26+, so per-task
    /// heatmaps cannot rely on system section separation. The List supplies
    /// the content inset; the background expands back to the native grouped
    /// card boundary so the content is not inset twice.
    func homeVisualizationListCard(
        accessibilityIdentifier: String
    ) -> some View {
        padding(.vertical, AppLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: AppLayout.nativeGroupedCardRadius,
                    style: .continuous
                )
                .fill(AppColors.cardBackground)
                .padding(.horizontal, -AppLayout.cardPadding)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(accessibilityIdentifier)
            .padding(.vertical, 5)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
