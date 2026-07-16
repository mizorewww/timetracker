import SwiftUI

struct SyncRecoverySettingsSection: View {
    let pendingConflict: SyncConflictPrompt?
    let isWorking: Bool
    let onReplaceCloud: () -> Void
    let onReplaceDevice: () -> Void

    var body: some View {
        Section {
            if let pendingConflict {
                SyncRecoveryCopySummaryRow(
                    title: AppStrings.localized("settings.syncRecovery.thisDevice"),
                    summary: pendingConflict.localSummary,
                    systemImage: "iphone",
                    tint: .orange
                )
                .accessibilityIdentifier("settings.syncRecovery.localSummary")

                SyncRecoveryCopySummaryRow(
                    title: AppStrings.localized("settings.syncRecovery.iCloud"),
                    summary: pendingConflict.cloudSummary,
                    systemImage: "icloud.fill",
                    tint: .blue
                )
                .accessibilityIdentifier("settings.syncRecovery.cloudSummary")
            }

            Button(role: .destructive, action: onReplaceCloud) {
                SettingsDestructiveActionLabel(
                    title: AppStrings.localized("settings.syncRecovery.replaceCloud"),
                    systemImage: "icloud.and.arrow.up.fill"
                )
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityIdentifier("settings.syncRecovery.replaceCloud")

            Button(role: .destructive, action: onReplaceDevice) {
                SettingsDestructiveActionLabel(
                    title: AppStrings.localized("settings.syncRecovery.replaceDevice"),
                    systemImage: "icloud.and.arrow.down.fill"
                )
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityIdentifier("settings.syncRecovery.replaceDevice")
        } header: {
            SettingsHeader(
                symbol: pendingConflict == nil ? "lifepreserver.fill" : "exclamationmark.triangle.fill",
                title: AppStrings.localized(
                    pendingConflict == nil
                        ? "settings.syncRecovery.title"
                        : "settings.syncRecovery.conflictTitle"
                )
            )
        } footer: {
            Text(
                .app(
                    pendingConflict == nil
                        ? "settings.syncRecovery.footer"
                        : "settings.syncRecovery.conflictFooter"
                )
            )
        }
    }
}

private struct SyncRecoveryCopySummaryRow: View {
    let title: String
    let summary: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .settingsRowSeparatorAligned()
    }
}
