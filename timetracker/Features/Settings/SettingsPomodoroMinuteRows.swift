import SwiftUI

struct SettingsPomodoroMinuteWheelRow: View {
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
