import SwiftUI

struct DisplayTimingSettingsSection: View {
    let preferredColorScheme: Binding<String>
    let allowParallelTimers: Binding<Bool>
    let showGrossAndWallTogether: Binding<Bool>

    var body: some View {
        Section {
            Picker(AppStrings.localized("settings.appearance"), selection: preferredColorScheme) {
                Text(.app("settings.appearance.system")).tag("system")
                Text(.app("settings.appearance.light")).tag("light")
                Text(.app("settings.appearance.dark")).tag("dark")
            }
            .pickerStyle(.segmented)

            Toggle(AppStrings.localized("settings.allowParallelTimers"), isOn: allowParallelTimers)
            Toggle(AppStrings.localized("settings.showWallGross"), isOn: showGrossAndWallTogether)
        } header: {
            SettingsHeader(symbol: "paintbrush.pointed.fill", title: AppStrings.localized("settings.displayTiming"))
        } footer: {
            Text(.app("settings.displayTiming.footer"))
        }
    }
}

struct PomodoroSettingsSection: View {
    let defaultMode: Binding<String>
    let focusMinutes: Binding<Int>
    let breakMinutes: Binding<Int>
    let rounds: Binding<Int>
    let onPresetSelected: (PomodoroPreset) -> Void

    private var minuteFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 480
        return formatter
    }

    var body: some View {
        Section {
            Picker(AppStrings.localized("settings.defaultMode"), selection: defaultMode) {
                ForEach(PomodoroPreset.allCases) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
            }
            .onChange(of: defaultMode.wrappedValue) { _, newValue in
                guard let preset = PomodoroPreset(rawValue: newValue), preset != .custom else { return }
                onPresetSelected(preset)
            }

            TextField(AppStrings.localized("settings.focusMinutes"), value: focusMinutes, formatter: minuteFormatter)
            TextField(AppStrings.localized("settings.breakMinutes"), value: breakMinutes, formatter: minuteFormatter)
            TextField(AppStrings.localized("settings.defaultRounds"), value: rounds, formatter: minuteFormatter)
        } header: {
            SettingsHeader(symbol: "timer", title: AppStrings.pomodoro)
        } footer: {
            Text(.app("settings.pomodoro.footer"))
        }
    }
}

struct CountdownSettingsSection: View {
    let events: [CountdownEvent]
    let onChangeTitle: (CountdownEvent, String) -> Void
    let onChangeDate: (CountdownEvent, Date) -> Void
    let onDelete: (CountdownEvent) -> Void
    let onAdd: () -> Void

    var body: some View {
        Section {
            if events.isEmpty {
                Text(.app("settings.countdown.empty"))
                    .foregroundStyle(.secondary)
            }

            ForEach(events) { event in
                CountdownEventSettingsRow(
                    event: event,
                    onChangeTitle: { title in
                        onChangeTitle(event, title)
                    },
                    onChangeDate: { date in
                        onChangeDate(event, date)
                    },
                    onDelete: {
                        onDelete(event)
                    }
                )
            }

            Button(action: onAdd) {
                SettingsActionLabel(title: AppStrings.localized("settings.countdown.add"), systemImage: "plus")
            }
        } header: {
            SettingsHeader(symbol: "calendar.badge.clock", title: AppStrings.localized("settings.countdown"))
        } footer: {
            Text(.app("settings.countdown.footer"))
        }
    }
}

struct SyncSettingsSection: View {
    let cloudSyncEnabled: Binding<Bool>
    let currentStorageValue: String
    let feedback: SyncFeedback
    let pendingConflict: SyncConflictPrompt?
    let isCheckingSync: Bool
    let onCheckSync: () -> Void
    let onForceSync: () -> Void
    let onUploadLocal: () -> Void
    let onDownloadCloud: () -> Void

    var body: some View {
        Section {
            SettingsStatusRow(feedback: feedback)

            if pendingConflict != nil {
                Button(action: onUploadLocal) {
                    SettingsActionLabel(
                        title: AppStrings.localized("dialog.syncConflict.uploadLocal"),
                        systemImage: "arrow.up.icloud"
                    )
                }

                Button(action: onDownloadCloud) {
                    SettingsActionLabel(
                        title: AppStrings.localized("dialog.syncConflict.downloadCloud"),
                        systemImage: "arrow.down.icloud"
                    )
                }
            }

            Toggle(isOn: cloudSyncEnabled) {
                Label(AppStrings.localized("settings.icloud"), systemImage: "icloud")
            }

            LabeledContent(
                AppStrings.localized("settings.currentStorage"),
                value: currentStorageValue
            )

            Button(action: onCheckSync) {
                SettingsActionLabel(
                    title: isCheckingSync ? AppStrings.localized("settings.checking") : AppStrings.localized("settings.checkSync"),
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(isCheckingSync)

            Button(action: onForceSync) {
                SettingsActionLabel(title: AppStrings.localized("settings.forceSync"), systemImage: "arrow.clockwise.icloud")
            }
            .disabled(isCheckingSync)
        } header: {
            SettingsHeader(symbol: "icloud.fill", title: AppStrings.localized("settings.sync"))
        } footer: {
            Text(.app("settings.sync.footer"))
        }
    }
}
