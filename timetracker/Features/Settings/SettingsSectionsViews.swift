import SwiftUI

struct DisplayTimingSettingsSection: View {
    let preferredColorScheme: Binding<String>
    let allowParallelTimers: Binding<Bool>
    let showGrossAndWallTogether: Binding<Bool>

    var body: some View {
        Section {
            Picker(selection: preferredColorScheme) {
                Text(.app("settings.appearance.system")).tag("system")
                Text(.app("settings.appearance.light")).tag("light")
                Text(.app("settings.appearance.dark")).tag("dark")
            } label: {
                SettingsRowLabel(
                    title: AppStrings.localized("settings.appearance"),
                    systemImage: "circle.lefthalf.filled",
                    tint: .purple
                )
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.appearance")

            Toggle(isOn: allowParallelTimers) {
                SettingsRowLabel(
                    title: AppStrings.localized("settings.allowParallelTimers"),
                    systemImage: "timer.circle",
                    tint: .orange
                )
            }
            .accessibilityIdentifier("settings.allowParallelTimers")
            Toggle(isOn: showGrossAndWallTogether) {
                SettingsRowLabel(
                    title: AppStrings.localized("settings.showWallGross"),
                    systemImage: "rectangle.split.2x1",
                    tint: .teal
                )
            }
            .accessibilityIdentifier("settings.showWallGross")
        } header: {
            SettingsHeader(symbol: "paintbrush.pointed.fill", title: AppStrings.localized("settings.displayTiming"))
        } footer: {
            Text(.app("settings.displayTiming.footer"))
        }
    }
}
