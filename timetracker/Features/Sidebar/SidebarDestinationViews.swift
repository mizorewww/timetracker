import SwiftUI

struct SidebarDestinationLabel: View {
    let destination: TimeTrackerStore.DesktopDestination
    let count: Int?

    var body: some View {
        HStack {
            Label {
                Text(destination.title)
            } icon: {
                SidebarTile(visual: destination.visual)
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
}

/// Solid destination tile, sized to the platform's sidebar row.
struct SidebarTile: View {
    let visual: DestinationVisual

    var body: some View {
        AppIconTile(systemImage: visual.symbolName, tint: visual.tint, style: .solid, size: size)
    }

    #if os(macOS)
    private let size: CGFloat = 22
    #else
    private let size: CGFloat = 30
    #endif
}
