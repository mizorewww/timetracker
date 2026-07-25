import SwiftUI

struct SidebarRevealButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(AppStrings.localized("sidebar.show"), systemImage: "sidebar.left")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel(AppStrings.localized("sidebar.show"))
        .accessibilityIdentifier("sidebar.show")
        #if os(macOS)
            .help(AppStrings.localized("sidebar.show"))
        #endif
    }
}
