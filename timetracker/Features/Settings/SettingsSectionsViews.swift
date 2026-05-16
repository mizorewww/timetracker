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
    let plans: Binding<[PomodoroPlan]>

    var body: some View {
        Group {
            Section {
                if plans.wrappedValue.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        SettingsRowIcon(systemImage: "timer", tint: .gray)
                        Text(.app("pomodoro.emptyPlans"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .settingsRowSeparatorAligned()
                }
            } header: {
                SettingsHeader(symbol: "timer", title: AppStrings.pomodoro)
            } footer: {
                Text(.app("settings.pomodoro.footer"))
            }

            ForEach(plans.wrappedValue) { plan in
                Section {
                    PomodoroPlanSettingsRows(
                        plan: binding(for: plan),
                        onDelete: {
                            delete(plan)
                        }
                    )
                } header: {
                    SettingsHeader(
                        symbol: ChecklistVisualSanitizer.sanitizedIcon(plan.iconName),
                        title: plan.displayName
                    )
                }
            }

            Section {
                Button(action: addPlan) {
                    SettingsActionLabel(
                        title: AppStrings.localized("pomodoro.addPlan"),
                        systemImage: "plus.circle.fill",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func binding(for plan: PomodoroPlan) -> Binding<PomodoroPlan> {
        Binding {
            plans.wrappedValue.first { $0.id == plan.id } ?? plan
        } set: { updatedPlan in
            var updatedPlans = plans.wrappedValue
            if let index = updatedPlans.firstIndex(where: { $0.id == plan.id }) {
                updatedPlans[index] = updatedPlan.normalized()
            } else {
                updatedPlans.append(updatedPlan.normalized())
            }
            plans.wrappedValue = updatedPlans
        }
    }

    private func addPlan() {
        var updatedPlans = plans.wrappedValue
        updatedPlans.append(.newPlan)
        plans.wrappedValue = updatedPlans
    }

    private func delete(_ plan: PomodoroPlan) {
        plans.wrappedValue = plans.wrappedValue.filter { $0.id != plan.id }
    }
}

private struct PomodoroPlanSettingsRows: View {
    @Binding var plan: PomodoroPlan
    let onDelete: () -> Void

    var body: some View {
        SettingsTextFieldRow(
            title: AppStrings.localized("pomodoro.planName"),
            text: $plan.name,
            systemImage: "textformat",
            tint: .blue,
            textAlignment: .trailing
        )

        HStack(spacing: 12) {
            SettingsRowLabel(
                title: AppStrings.localized("editor.task.symbolColor"),
                systemImage: "paintpalette",
                tint: .purple
            )

            Spacer(minLength: 8)

            SymbolColorPickerButton(
                colors: TaskColorPalette.hexValues,
                symbolName: $plan.iconName,
                colorHex: $plan.colorHex
            )
        }
        .settingsRowSeparatorAligned()

        SettingsPomodoroMinuteWheelRow(
            title: AppStrings.localized("pomodoro.focus"),
            systemImage: "brain.head.profile",
            tint: .indigo,
            value: $plan.focusMinutes
        )

        SettingsPomodoroMinuteWheelRow(
            title: AppStrings.localized("pomodoro.shortBreak"),
            systemImage: "cup.and.saucer",
            tint: .mint,
            value: $plan.shortBreakMinutes
        )

        SettingsPomodoroMinuteWheelRow(
            title: AppStrings.localized("pomodoro.longBreak"),
            systemImage: "moon.zzz",
            tint: .orange,
            value: $plan.longBreakMinutes
        )

        Stepper(value: $plan.rounds, in: PomodoroPlan.roundRange) {
            HStack(spacing: 12) {
                SettingsRowLabel(
                    title: AppStrings.localized("pomodoro.rounds"),
                    systemImage: "repeat.circle",
                    tint: .pink
                )

                Spacer(minLength: 8)

                Text("\(plan.rounds)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .settingsRowSeparatorAligned()

        Toggle(isOn: $plan.allowsSystemClock) {
            SettingsRowLabel(
                title: AppStrings.localized("pomodoro.systemClock"),
                systemImage: "alarm",
                tint: .orange
            )
        }

        Button(role: .destructive, action: onDelete) {
            SettingsActionLabel(
                title: AppStrings.localized("pomodoro.deletePlan"),
                systemImage: "trash",
                tint: .red
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPomodoroMinuteWheelRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Binding var value: Int
    @State private var isPickerPresented = false

    private var normalizedValue: Binding<Int> {
        Binding {
            PomodoroPlan.normalizedMinute(value)
        } set: { newValue in
            value = PomodoroPlan.normalizedMinute(newValue)
        }
    }

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 12) {
                SettingsRowIcon(systemImage: systemImage, tint: tint)

                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(String(format: AppStrings.localized("common.minutes"), normalizedValue.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsRowSeparatorAligned()
        .popover(isPresented: $isPickerPresented) {
            minutePopoverContent
        }
    }

    private var minutePopoverContent: some View {
        minuteSelectionContent
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(width: 240)
            .fixedSize(horizontal: false, vertical: true)
            .settingsPopoverAdaptation()
    }

    @ViewBuilder
    private var minuteSelectionContent: some View {
        #if os(iOS)
        Picker(title, selection: normalizedValue) {
            ForEach(PomodoroPlan.minuteOptions, id: \.self) { minute in
                Text(String(format: AppStrings.localized("common.minutes"), minute))
                    .tag(minute)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: 208, height: 216)
        #else
        SettingsPomodoroMinuteChoiceList(
            title: title,
            value: $value,
            isPickerPresented: $isPickerPresented
        )
        #endif
    }
}

private struct SettingsPomodoroMinuteChoiceList: View {
    let title: String
    @Binding var value: Int
    @Binding var isPickerPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            minuteButton(5)
            minuteButton(10)
            minuteButton(15)
            minuteButton(20)
            minuteButton(25)
            minuteButton(30)
            minuteButton(35)
            minuteButton(40)
            minuteButton(45)
            minuteButton(50)
            minuteButton(55)
            minuteButton(60)
        }
    }

    private func minuteButton(_ minute: Int) -> some View {
        Button {
            value = PomodoroPlan.normalizedMinute(minute)
            isPickerPresented = false
        } label: {
            HStack {
                Text(String(format: AppStrings.localized("common.minutes"), minute))
                Spacer()
                if PomodoroPlan.normalizedMinute(value) == minute {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CountdownSettingsSection: View {
    let events: [CountdownEvent]
    let onChangeTitle: (CountdownEvent, String) -> Void
    let onChangeDate: (CountdownEvent, Date) -> Void
    let onDelete: (CountdownEvent) -> Void
    let onAdd: () -> Void

    var body: some View {
        Group {
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
            } header: {
                SettingsHeader(symbol: "calendar.badge.clock", title: AppStrings.localized("settings.countdown"))
            } footer: {
                Text(.app("settings.countdown.footer"))
            }

            ForEach(events) { event in
                Section {
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
                } header: {
                    SettingsHeader(
                        symbol: "calendar",
                        title: event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? AppStrings.localized("settings.countdown.eventName")
                            : event.title
                    )
                }
            }

            Section {
                Button(action: onAdd) {
                    SettingsActionLabel(
                        title: AppStrings.localized("settings.countdown.add"),
                        systemImage: "calendar.badge.plus",
                        tint: .green
                    )
                }
                .buttonStyle(.plain)
            }
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
