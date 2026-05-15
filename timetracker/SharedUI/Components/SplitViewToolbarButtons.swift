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

struct InspectorToggleButton: View {
    let isPresented: Bool
    let isEnabled: Bool
    let action: () -> Void

    private var title: String {
        isPresented ? AppStrings.localized("inspector.hide") : AppStrings.localized("inspector.show")
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "sidebar.right")
                .labelStyle(.iconOnly)
        }
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        #if os(macOS)
        .help(title)
        #endif
    }
}
