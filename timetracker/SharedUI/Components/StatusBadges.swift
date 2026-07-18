import SwiftUI

struct AppStatusBadge: View {
    let title: String
    var systemImage: String?
    var tint: Color = .secondary
    var compact = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .labelStyle(.titleAndIcon)
        .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct RunningStatusBadge: View {
    var compact = true

    var body: some View {
        AppStatusBadge(
            title: AppStrings.running,
            systemImage: "play.fill",
            tint: .green,
            compact: compact
        )
    }
}
