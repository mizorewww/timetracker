import SwiftUI

#if os(macOS)
private let cardTitleFont = Font.subheadline.weight(.semibold)
#else
private let cardTitleFont = Font.caption2.weight(.semibold)
#endif

extension View {
    /// The design language's card title: small, semibold, uppercase,
    /// tracked and secondary.
    func appCardTitleStyle() -> some View {
        font(cardTitleFont)
            .textCase(.uppercase)
            .tracking(0.44)
            .foregroundStyle(.secondary)
    }
}

struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .appCardTitleStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SettingsHeader: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
    }
}
