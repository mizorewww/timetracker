import SwiftUI

struct DataSettingsSection: View {
    let allowsPermanentCleanup: Bool
    let operationMessage: String?
    let onExport: () -> Void
    let onOptimize: () -> Void

    var body: some View {
        Section {
            Button(action: onExport) {
                SettingsActionLabel(
                    title: AppStrings.localized("settings.exportJSON"),
                    systemImage: "curlybraces.square",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)

            if allowsPermanentCleanup {
                Button(role: .destructive, action: onOptimize) {
                    SettingsDestructiveActionLabel(
                        title: AppStrings.localized("settings.optimizeDatabase"),
                        systemImage: "externaldrive.badge.checkmark"
                    )
                }
                .buttonStyle(.plain)
            }

            if let operationMessage {
                Label {
                    Text(operationMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .accessibilityIdentifier("settings.data.operationMessage")
            }
        } header: {
            SettingsHeader(symbol: "doc.text.fill", title: AppStrings.localized("settings.data"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(.app("settings.data.footer"))
                if allowsPermanentCleanup {
                    Text(.app("settings.data.cleanupFooter"))
                }
            }
        }
    }
}

struct MaintenanceSettingsSection: View {
    let taskCount: Int
    let timeRecordCount: Int
    let pomodoroCount: Int
    let cloudAccount: String
    let cloudContainer: String
    let allowsDemoDataCreation: Bool
    let hasDemoData: Bool
    let onRebuildDemoData: () -> Void
    let onClearDemoData: () -> Void
    let onResetAllData: () -> Void

    var body: some View {
        Section {
            SettingsValueRow(title: AppStrings.tasks, value: "\(taskCount)", systemImage: "checklist", tint: .blue)
            SettingsValueRow(title: AppStrings.localized("settings.timeRecords"), value: "\(timeRecordCount)", systemImage: "clock", tint: .orange)
            SettingsValueRow(title: AppStrings.pomodoro, value: "\(pomodoroCount)", systemImage: "timer", tint: .red)
            SettingsValueRow(title: AppStrings.localized("settings.cloudAccount"), value: cloudAccount, systemImage: "person.crop.circle.badge.checkmark", tint: .green)
            SettingsValueRow(title: AppStrings.localized("settings.icloudContainer"), value: cloudContainer, systemImage: "shippingbox", tint: .cyan)
            if allowsDemoDataCreation {
                Button(role: .destructive, action: onRebuildDemoData) {
                    SettingsDestructiveActionLabel(
                        title: AppStrings.localized("settings.rebuildDemoData"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.plain)
            }
            if hasDemoData {
                Button(role: .destructive, action: onClearDemoData) {
                    SettingsDestructiveActionLabel(
                        title: AppStrings.localized("settings.clearDemoData"),
                        systemImage: "trash"
                    )
                }
                .buttonStyle(.plain)
            }
            Button(role: .destructive, action: onResetAllData) {
                SettingsDestructiveActionLabel(
                    title: AppStrings.localized("settings.resetData"),
                    systemImage: "trash.slash"
                )
            }
            .buttonStyle(.plain)
        } header: {
            SettingsHeader(symbol: "wrench.and.screwdriver.fill", title: AppStrings.localized("settings.maintenance"))
        }
    }
}

struct AboutSettingsSection: View {
    var body: some View {
        Section {
            AboutAppSummary()
            SettingsValueRow(title: AppStrings.localized("settings.about.version"), value: AppBuildInfo.versionSummary, systemImage: "number.circle", tint: .blue)
            SettingsValueRow(title: AppStrings.localized("settings.about.branch"), value: AppBuildInfo.gitBranch, systemImage: "point.3.connected.trianglepath.dotted", tint: .purple)
            SettingsValueRow(title: AppStrings.localized("settings.about.commit"), value: AppBuildInfo.gitCommit + (AppBuildInfo.isDirtyBuild ? " *" : ""), systemImage: "chevron.left.forwardslash.chevron.right", tint: .orange)
            SettingsValueRow(title: AppStrings.localized("settings.about.built"), value: AppBuildInfo.buildDate, systemImage: "hammer", tint: .gray)
        } header: {
            SettingsHeader(symbol: "info.circle.fill", title: AppStrings.localized("settings.about"))
        } footer: {
            Text(.app("settings.about.footer"))
        }
    }
}
