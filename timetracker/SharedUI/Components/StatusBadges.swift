import SwiftUI

struct AppStatusBadge: View {
    let title: String
    var systemImage: String?
    var tint: Color = .secondary
    var compact = false

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
        .lineLimit(1)
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

struct TaskStatusBadge: View {
    let status: TaskStatus
    var compact = true

    var body: some View {
        AppStatusBadge(
            title: status.displayName,
            systemImage: status.symbolName,
            tint: Color(hex: status.colorHex) ?? .secondary,
            compact: compact
        )
    }
}
