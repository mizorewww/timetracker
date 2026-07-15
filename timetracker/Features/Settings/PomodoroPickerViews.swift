import SwiftUI

struct SettingsPomodoroMinuteWheelRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    @Binding var value: Int
    @State private var isPickerPresented = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            minuteRowLabel
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppLayout.minimumInteractiveTarget)
        .settingsRowSeparatorAligned()
        .popover(isPresented: $isPickerPresented) {
            minutePopoverContent
        }
    }

    private var minutePopoverContent: some View {
        minuteSelectionContent
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .settingsPopoverContentFrame(idealWidth: 240)
            .fixedSize(horizontal: false, vertical: true)
            .settingsPopoverAdaptation()
    }

    @ViewBuilder
    private var minuteRowLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    SettingsRowIcon(systemImage: systemImage, tint: tint)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Text(String(format: AppStrings.localized("common.minutes"), normalizedValue.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.leading, 40)
            }
        } else {
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
                    .accessibilityHidden(true)
            }
        }
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

            ForEach(PomodoroPlan.minuteOptions, id: \.self) { minute in
                minuteButton(minute)
            }
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
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: AppLayout.minimumInteractiveTarget)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(
            PomodoroPlan.normalizedMinute(value) == minute ? .isSelected : []
        )
    }
}
