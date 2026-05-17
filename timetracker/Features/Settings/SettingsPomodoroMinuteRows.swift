import SwiftUI

struct SettingsPomodoroMinutePickerRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Binding var value: Int

    private var normalizedValue: Binding<Int> {
        Binding {
            PomodoroPlan.normalizedMinute(value)
        } set: { newValue in
            value = PomodoroPlan.normalizedMinute(newValue)
        }
    }

    var body: some View {
        Picker(selection: normalizedValue) {
            ForEach(PomodoroPlan.minuteOptions, id: \.self) { minute in
                Text(String(format: AppStrings.localized("common.minutes"), minute))
                    .tag(minute)
            }
        } label: {
            SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .pickerStyle(.menu)
        .settingsRowSeparatorAligned()
    }
}
