import SwiftUI

struct SidebarDestinationLabel: View {
    let destination: TimeTrackerStore.DesktopDestination
    let count: Int?

    var body: some View {
        HStack {
            Label(destination.title, systemImage: destination.symbolName)
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
