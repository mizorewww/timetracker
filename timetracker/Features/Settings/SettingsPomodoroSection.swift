import SwiftUI

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
