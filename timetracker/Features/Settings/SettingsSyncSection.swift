import SwiftUI

struct SyncSettingsSection: View {
    let cloudSyncEnabled: Binding<Bool>
    let currentStorageValue: String
    let feedback: SyncFeedback
    let pendingConflict: SyncConflictPrompt?
    let isCheckingSync: Bool
    let onCheckSync: () -> Void
    let onForceSync: () -> Void
    let onForceUploadLocal: () -> Void
    let onForceDownloadCloud: () -> Void
    let onUploadLocal: () -> Void
    let onDownloadCloud: () -> Void

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
            .accessibilityIdentifier("settings.icloud.toggle")

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
            .accessibilityIdentifier("settings.checkSync")

            Button(action: onForceSync) {
                SettingsActionLabel(
                    title: AppStrings.localized("settings.forceSync"),
                    systemImage: "arrow.clockwise.icloud",
                    tint: .blue
                )
            }
            .buttonStyle(.plain)
            .disabled(isCheckingSync)
            .accessibilityIdentifier("settings.forceSync")

            Button {
                if pendingConflict == nil {
                    onForceUploadLocal()
                } else {
                    onUploadLocal()
                }
            } label: {
                SettingsActionLabel(
                    title: uploadTitle,
                    systemImage: "icloud.and.arrow.up.fill",
                    tint: .green,
                    secondaryTint: .blue
                )
            }
            .buttonStyle(.plain)
            .disabled(isCheckingSync)
            .accessibilityIdentifier("settings.forceUpload")

            Button {
                if pendingConflict == nil {
                    onForceDownloadCloud()
                } else {
                    onDownloadCloud()
                }
            } label: {
                SettingsActionLabel(
                    title: downloadTitle,
                    systemImage: "icloud.and.arrow.down.fill",
                    tint: .cyan,
                    secondaryTint: .blue
                )
            }
            .buttonStyle(.plain)
            .disabled(isCheckingSync)
            .accessibilityIdentifier("settings.forceDownload")
        } header: {
            SettingsHeader(symbol: "icloud.fill", title: AppStrings.localized("settings.sync"))
        } footer: {
            Text(.app("settings.sync.footer"))
        }
    }

    private var uploadTitle: String {
        pendingConflict == nil
            ? AppStrings.localized("settings.forceUploadICloud")
            : AppStrings.localized("dialog.syncConflict.uploadLocal")
    }

    private var downloadTitle: String {
        pendingConflict == nil
            ? AppStrings.localized("settings.forceDownloadICloud")
            : AppStrings.localized("dialog.syncConflict.downloadCloud")
    }
}
