import SwiftUI

struct SettingsActionLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = .accentColor
    var secondaryTint: Color?

    var body: some View {
        SettingsActionRowContent(
            title: title,
            systemImage: systemImage,
            iconTint: tint,
            secondaryIconTint: secondaryTint,
            titleColor: .primary
        )
    }
}

struct SettingsDestructiveActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        SettingsActionRowContent(
            title: title,
            systemImage: systemImage,
            iconTint: .red,
            secondaryIconTint: nil,
            titleColor: .red
        )
    }
}

private struct SettingsActionRowContent: View {
    let title: String
    let systemImage: String
    let iconTint: Color
    let secondaryIconTint: Color?
    let titleColor: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(
                systemImage: systemImage,
                tint: iconTint,
                secondaryTint: secondaryIconTint
            )

            Text(title)
                .font(.body)
                .foregroundStyle(titleColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .settingsRowSeparatorAligned()
    }
}
