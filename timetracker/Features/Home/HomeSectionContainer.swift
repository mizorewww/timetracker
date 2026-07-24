import SwiftUI

enum HomeSectionContainer {
    case card
    case listSection
}

extension View {
    func homeVisualizationListSection() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Draws a card that matches the native inset-grouped card look
    /// (large continuous corners, grouped background, no stroke) while
    /// keeping every visualization in its own card. Consecutive grouped
    /// `Section`s merge into one continuous card on iOS 26+, so per-task
    /// heatmaps cannot rely on system section separation.
    func homeVisualizationListCard(
        accessibilityIdentifier: String
    ) -> some View {
        self
            .padding(16)
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
