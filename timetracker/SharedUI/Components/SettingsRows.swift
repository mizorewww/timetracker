import SwiftUI

extension View {
    func settingsRowSeparatorAligned() -> some View {
        modifier(SettingsRowSeparatorAlignmentModifier())
    }
}

private struct SettingsRowSeparatorAlignmentModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        #else
        content
        #endif
    }
}

/// Solid design-language tile for a settings or navigation row.
struct SettingsRowIcon: View {
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        AppIconTile(systemImage: systemImage, tint: tint, style: .solid, size: AppLayout.rowIconSize)
    }
}

struct SettingsRowLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .settingsRowSeparatorAligned()
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
                    Text(value)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, AppLayout.rowIconSize + 12)
                }
            } else {
                HStack(spacing: 12) {
                    SettingsRowIcon(systemImage: systemImage, tint: tint)

                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .settingsRowSeparatorAligned()
    }
}
