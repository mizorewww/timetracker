import SwiftUI

struct AppSectionHeader: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var trailing: String?
    var trailingTint: Color = .blue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if let trailing, !trailing.isEmpty {
                Text(trailing)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(trailingTint)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        AppSectionHeader(title: title, trailing: trailing)
    }
}

struct SettingsHeader: View {
    let symbol: String
    let title: String

    var body: some View {
        AppSectionHeader(title: title, systemImage: symbol)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isHeader)
    }
}
