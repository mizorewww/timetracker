import SwiftUI

struct SidebarDestinationLabel: View {
    let destination: TimeTrackerStore.DesktopDestination
    let count: Int?
    let isSelected: Bool
    /// Bumped on selection so the tile's symbol bounces once.
    @State private var selectionCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Label {
                Text(destination.title)
            } icon: {
                SidebarTile(visual: destination.visual)
                    .symbolEffect(.bounce, value: selectionCount)
                    .symbolEffectsRemoved(reduceMotion)
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
        .onChange(of: isSelected) { _, isSelected in
            if isSelected {
                selectionCount += 1
            }
        }
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
