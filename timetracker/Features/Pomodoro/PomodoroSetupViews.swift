import SwiftUI

struct PomodoroSetupCard: View {
    @ObservedObject var store: TimeTrackerStore
    @Binding var focusMinutes: Int
    @Binding var breakMinutes: Int
    @Binding var targetRounds: Int

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 480
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(.app("pomodoro.beforeStart"))
                    .font(.headline)
                Text(.app("pomodoro.beforeStart.message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker(AppStrings.localized("pomodoro.chooseTask"), selection: Binding<UUID?>(
                get: { store.selectedTaskID },
                set: { store.selectedTaskID = $0 }
            )) {
                Text(.app("pomodoro.chooseTask")).tag(UUID?.none)
                ForEach(store.tasks) { task in
                    Text(store.path(for: task)).tag(Optional(task.id))
                }
            }

            Menu(AppStrings.localized("pomodoro.applyPreset")) {
                ForEach(PomodoroPreset.allCases.filter { $0 != .custom }) { preset in
                    Button(preset.title) {
                        focusMinutes = preset.focusMinutes
                        breakMinutes = preset.breakMinutes
                    }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text(.app("pomodoro.focus"))
                        .foregroundStyle(.secondary)
                    TextField(AppStrings.localized("pomodoro.minuteField"), value: $focusMinutes, formatter: numberFormatter)
                        .textFieldStyle(.roundedBorder)
                    Text(.app("pomodoro.minuteField"))
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text(.app("pomodoro.break"))
                        .foregroundStyle(.secondary)
                    TextField(AppStrings.localized("pomodoro.minuteField"), value: $breakMinutes, formatter: numberFormatter)
                        .textFieldStyle(.roundedBorder)
                    Text(.app("pomodoro.minuteField"))
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text(.app("pomodoro.rounds"))
                        .foregroundStyle(.secondary)
                    TextField(AppStrings.localized("pomodoro.roundField"), value: $targetRounds, formatter: numberFormatter)
                        .textFieldStyle(.roundedBorder)
                    Text(.app("pomodoro.roundUnit"))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                PomodoroPlanMetric(title: AppStrings.localized("pomodoro.focus"), value: String(format: AppStrings.localized("common.minutes"), focusMinutes))
                PomodoroPlanMetric(title: AppStrings.localized("pomodoro.break"), value: String(format: AppStrings.localized("common.minutes"), breakMinutes))
                PomodoroPlanMetric(title: AppStrings.localized("pomodoro.rounds"), value: "\(targetRounds)")
            }

            Button {
                store.startPomodoroForSelectedTask(
                    focusSeconds: max(1, focusMinutes) * 60,
                    breakSeconds: max(1, breakMinutes) * 60,
                    targetRounds: max(1, targetRounds)
                )
            } label: {
                Label(AppStrings.localized("pomodoro.startFocus"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.selectedTaskID == nil)
            .accessibilityIdentifier("pomodoro.startFocus")
        }
        .padding(18)
        .appCard(padding: 0)
    }
}

private struct PomodoroPlanMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
