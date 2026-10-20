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
        #if os(macOS)
        AppIconTile(systemImage: visual.symbolName, tint: visual.tint, style: .solid, size: 22)
        #else
        AppIconTile(systemImage: visual.symbolName, tint: visual.tint, style: .solid, size: 30)
        #endif
    }
}
