import SwiftUI

struct DisplayTimingSettingsSection: View {
    let allowParallelTimers: Binding<Bool>
    let showGrossAndWallTogether: Binding<Bool>

    var body: some View {
        Section {
            Toggle(isOn: allowParallelTimers) {
                SettingsRowLabel(
                    title: AppStrings.localized("settings.allowParallelTimers"),
                    systemImage: "timer.circle",
                    tint: .orange
                )
            }
            Toggle(isOn: showGrossAndWallTogether) {
                SettingsRowLabel(
                    title: AppStrings.localized("settings.showWallGross"),
                    systemImage: "rectangle.split.2x1",
                    tint: .teal
                )
            }
        } header: {
            SettingsHeader(symbol: "timer", title: AppStrings.localized("settings.displayTiming"))
        } footer: {
            Text(.app("settings.displayTiming.systemAppearanceFooter"))
        }
    }
}
