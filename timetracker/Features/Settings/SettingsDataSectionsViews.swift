import SwiftUI

struct DataSettingsSection: View {
    let onExport: () -> Void
    let onAddTime: () -> Void
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

            Button(action: onAddTime) {
                SettingsActionLabel(title: AppStrings.addTime, systemImage: "calendar.badge.plus", tint: .blue)
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onOptimize) {
                SettingsActionLabel(
                    title: AppStrings.localized("settings.optimizeDatabase"),
                    systemImage: "externaldrive.badge.checkmark",
                    tint: .red
                )
            }
            .buttonStyle(.plain)
        } header: {
            SettingsHeader(symbol: "doc.text.fill", title: AppStrings.localized("settings.data"))
        } footer: {
            Text(.app("settings.data.footer"))
        }
    }
}

struct LLMSettingsSection: View {
    let endpoint: Binding<String>
    let apiKey: Binding<String>
    let selectedModel: Binding<String>
    let availableModels: [String]
    let feedbackMessage: String?
    let isFetchingModels: Bool
    let onFetchModels: () -> Void

    var body: some View {
        Section {
            SettingsTextFieldRow(
                title: AppStrings.localized("settings.llm.endpoint"),
                text: endpoint,
                systemImage: "link",
                tint: .purple
            )

            SettingsTextFieldRow(
                title: AppStrings.localized("settings.llm.apiKey"),
                text: apiKey,
                systemImage: "key.fill",
                tint: .orange,
                isSecure: true
            )

            modelSelectionRow

            if let feedbackMessage, !feedbackMessage.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    SettingsRowIcon(systemImage: "info.circle", tint: .gray)
                    Text(feedbackMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .settingsRowSeparatorAligned()
            }
        } header: {
            SettingsHeader(symbol: "sparkles", title: AppStrings.localized("settings.llm"))
        } footer: {
            Text(.app("settings.llm.footer"))
        }
    }

    @ViewBuilder
    private var modelSelectionRow: some View {
        if isFetchingModels {
            SettingsModelSelectionRow(
                title: AppStrings.localized("settings.llm.model"),
                value: AppStrings.localized("settings.llm.fetching"),
                isLoading: true
            )
        } else if availableModels.isEmpty {
            Button(action: onFetchModels) {
                SettingsModelSelectionRow(
                    title: AppStrings.localized("settings.llm.model"),
                    value: AppStrings.localized("settings.llm.noModels"),
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        } else {
            Picker(selection: selectedModel) {
                ForEach(availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            } label: {
                SettingsRowLabel(
                    title: AppStrings.localized("settings.llm.model"),
                    systemImage: "cpu",
                    tint: .indigo
                )
            }
        }
    }
}

private struct SettingsModelSelectionRow: View {
    let title: String
    let value: String
    var isLoading = false
    var showsChevron = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                SettingsRowIcon(systemImage: "cpu", tint: .indigo)
            }

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .combine)
        .settingsRowSeparatorAligned()
    }
}

struct MaintenanceSettingsSection: View {
    let taskCount: Int
    let timeRecordCount: Int
    let pomodoroCount: Int
    let cloudAccount: String
    let cloudContainer: String
    let allowsDemoDataCreation: Bool
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
                    SettingsActionLabel(title: AppStrings.localized("settings.rebuildDemoData"), systemImage: "arrow.clockwise", tint: .red)
                }
                .buttonStyle(.plain)
            }
            Button(role: .destructive, action: onClearDemoData) {
                SettingsActionLabel(title: AppStrings.localized("settings.clearDemoData"), systemImage: "trash", tint: .red)
            }
            .buttonStyle(.plain)
            Button(role: .destructive, action: onResetAllData) {
                SettingsActionLabel(title: AppStrings.localized("settings.resetData"), systemImage: "trash.slash", tint: .red)
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
