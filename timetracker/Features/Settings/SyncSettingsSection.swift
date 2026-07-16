import SwiftUI

struct SyncSettingsSection: View {
    let cloudSyncEnabled: Binding<Bool>
    let currentStorageValue: String
    let feedback: SyncFeedback
    let isCheckingSync: Bool
    let onCheckSync: () -> Void
    let onForceSync: () -> Void

    var body: some View {
        Section {
            SettingsStatusRow(feedback: feedback)

            Toggle(isOn: cloudSyncEnabled) {
                SettingsRowLabel(
                    title: AppStrings.localized("settings.icloud"),
                    systemImage: "icloud",
                    tint: .blue
                )
            }

            SettingsValueRow(
                title: AppStrings.localized("settings.currentStorage"),
                value: currentStorageValue,
                systemImage: "externaldrive.connected.to.line.below",
                tint: .cyan
            )

            Button(action: onCheckSync) {
                SettingsActionLabel(
                    title: isCheckingSync ? AppStrings.localized("settings.checking") : AppStrings.localized("settings.checkSync"),
                    systemImage: "arrow.clockwise",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
            .disabled(isCheckingSync)

            Button(action: onForceSync) {
                SettingsActionLabel(
                    title: AppStrings.localized("settings.forceSync"),
                    systemImage: "arrow.clockwise.icloud",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
            .disabled(isCheckingSync)
        } header: {
            SettingsHeader(symbol: "icloud.fill", title: AppStrings.localized("settings.sync"))
        } footer: {
            Text(.app("settings.sync.footer"))
        }
    }
}
