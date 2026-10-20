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
                    .accessibilityIdentifier("\(accessibilityIdentifier).title")
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

            trailing
        }
        .frame(minHeight: cardHeaderMinimumHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var cardHeaderMinimumHeight: CGFloat? {
        switch container {
        case .card:
            AppLayout.minimumInteractiveTarget
        case .listSection:
            nil
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch container {
        case .card:
            Text(title)
                .appCardTitleStyle()
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
    /// heatmaps cannot rely on system section separation. The row has no
    /// list insets, so the card spans the native grouped card boundary and
    /// insets its own content.
    func homeVisualizationListCard(
        accessibilityIdentifier: String
    ) -> some View {
        padding(AppLayout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppColors.cardBackground,
                in: RoundedRectangle(
                    cornerRadius: AppLayout.nativeGroupedCardRadius,
                    style: .continuous
                )
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(accessibilityIdentifier)
            .padding(.vertical, 5)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
