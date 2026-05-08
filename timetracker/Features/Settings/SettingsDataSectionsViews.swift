import SwiftUI

struct DataSettingsSection: View {
    let onExport: () -> Void
    let onAddTime: () -> Void
    let onOptimize: () -> Void

    var body: some View {
        Section {
            Button(action: onExport) {
                SettingsActionLabel(title: AppStrings.localized("settings.exportCSV"), systemImage: "square.and.arrow.down")
            }

            Button(action: onAddTime) {
                SettingsActionLabel(title: AppStrings.addTime, systemImage: "calendar.badge.plus")
            }

            Button(role: .destructive, action: onOptimize) {
                SettingsActionLabel(title: AppStrings.localized("settings.optimizeDatabase"), systemImage: "externaldrive.badge.checkmark")
            }
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
            TextField(AppStrings.localized("settings.llm.endpoint"), text: endpoint)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            SecureField(AppStrings.localized("settings.llm.apiKey"), text: apiKey)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            if availableModels.isEmpty {
                LabeledContent(
                    AppStrings.localized("settings.llm.model"),
                    value: AppStrings.localized("settings.llm.noModels")
                )
            } else {
                Picker(AppStrings.localized("settings.llm.model"), selection: selectedModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            Button(action: onFetchModels) {
                SettingsActionLabel(
                    title: isFetchingModels ? AppStrings.localized("settings.llm.fetching") : AppStrings.localized("settings.llm.fetchModels"),
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(isFetchingModels)

            if let feedbackMessage, !feedbackMessage.isEmpty {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsHeader(symbol: "sparkles", title: AppStrings.localized("settings.llm"))
        } footer: {
            Text(.app("settings.llm.footer"))
        }
    }
}

struct MaintenanceSettingsSection: View {
    let taskCount: Int
    let timeRecordCount: Int
    let pomodoroCount: Int
    let cloudAccount: String
    let cloudContainer: String
    let onRebuildDemoData: () -> Void
    let onClearDemoData: () -> Void

    var body: some View {
        Section {
            LabeledContent(AppStrings.tasks, value: "\(taskCount)")
            LabeledContent(AppStrings.localized("settings.timeRecords"), value: "\(timeRecordCount)")
            LabeledContent(AppStrings.pomodoro, value: "\(pomodoroCount)")
            LabeledContent(AppStrings.localized("settings.cloudAccount"), value: cloudAccount)
            LabeledContent(AppStrings.localized("settings.icloudContainer"), value: cloudContainer)
            Button(role: .destructive, action: onRebuildDemoData) {
                SettingsActionLabel(title: AppStrings.localized("settings.rebuildDemoData"), systemImage: "arrow.clockwise")
            }
            Button(role: .destructive, action: onClearDemoData) {
                SettingsActionLabel(title: AppStrings.localized("settings.clearDemoData"), systemImage: "trash")
            }
        } header: {
            SettingsHeader(symbol: "wrench.and.screwdriver.fill", title: AppStrings.localized("settings.maintenance"))
        }
    }
}

struct AboutSettingsSection: View {
    var body: some View {
        Section {
            AboutAppSummary()
            LabeledContent(AppStrings.localized("settings.about.version"), value: AppBuildInfo.versionSummary)
            LabeledContent(AppStrings.localized("settings.about.branch"), value: AppBuildInfo.gitBranch)
            LabeledContent(AppStrings.localized("settings.about.commit"), value: AppBuildInfo.gitCommit + (AppBuildInfo.isDirtyBuild ? " *" : ""))
            LabeledContent(AppStrings.localized("settings.about.built"), value: AppBuildInfo.buildDate)
        } header: {
            SettingsHeader(symbol: "info.circle.fill", title: AppStrings.localized("settings.about"))
        } footer: {
            Text(.app("settings.about.footer"))
        }
    }
}
