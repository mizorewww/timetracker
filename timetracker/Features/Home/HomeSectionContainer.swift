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

    func homeVisualizationListCard(
        accessibilityIdentifier: String
    ) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(padding: 0)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(accessibilityIdentifier)
            .padding(.vertical, 5)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
