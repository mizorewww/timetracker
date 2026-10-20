import SwiftUI

struct SidebarDestinationLabel: View {
    let destination: TimeTrackerStore.DesktopDestination
    let count: Int?

    var body: some View {
        HStack {
            Label {
                Text(destination.title)
            } icon: {
                SidebarTile(systemImage: destination.symbolName, tint: tint)
            }
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch destination {
        case .today: .orange
        case .inbox: .blue
        case .tasks: .green
        case .pomodoro: .pink
        case .analytics: .purple
        }
    }
}

/// Solid destination tile, sized to the platform's sidebar row.
struct SidebarTile: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        #if os(macOS)
        AppIconTile(systemImage: systemImage, tint: tint, style: .solid, size: 22)
        #else
        AppIconTile(systemImage: systemImage, tint: tint, style: .solid, size: 30)
        #endif
    }
}
