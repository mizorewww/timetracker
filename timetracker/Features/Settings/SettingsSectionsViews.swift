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
            Picker(selection: defaultMode) {
                ForEach(PomodoroPreset.allCases) { preset in
                    Text(preset.title).tag(preset.rawValue)
                }
            } label: {
                SettingsRowLabel(
                    title: AppStrings.localized("settings.defaultMode"),
                    systemImage: "dial.medium",
                    tint: .orange
                )
            }
            .onChange(of: defaultMode.wrappedValue) { _, newValue in
                guard let preset = PomodoroPreset(rawValue: newValue), preset != .custom else { return }
                onPresetSelected(preset)
            }

            SettingsNumberFieldRow(
                title: AppStrings.localized("settings.focusMinutes"),
                value: focusMinutes,
                formatter: minuteFormatter,
                systemImage: "brain.head.profile",
                tint: .indigo
            )
            SettingsNumberFieldRow(
                title: AppStrings.localized("settings.breakMinutes"),
                value: breakMinutes,
                formatter: minuteFormatter,
                systemImage: "cup.and.saucer",
                tint: .mint
            )
            SettingsNumberFieldRow(
                title: AppStrings.localized("settings.defaultRounds"),
                value: rounds,
                formatter: minuteFormatter,
                systemImage: "repeat.circle",
                tint: .pink
            )
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
                HStack(alignment: .top, spacing: 12) {
                    SettingsRowIcon(systemImage: "calendar.badge.exclamationmark", tint: .gray)
                    Text(.app("settings.countdown.empty"))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .settingsRowSeparatorAligned()
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
                SettingsActionLabel(
                    title: AppStrings.localized("settings.countdown.add"),
                    systemImage: "calendar.badge.plus",
                    tint: .green
                )
            }
            .buttonStyle(.plain)
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
