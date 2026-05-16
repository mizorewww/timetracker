import SwiftUI

struct AboutAppSummary: View {
    var body: some View {
        HStack(spacing: 14) {
            AppIconImage()
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppBuildInfo.displayName)
                    .font(.headline)
                Text(String(format: AppStrings.localized("settings.about.versionFormat"), AppBuildInfo.versionSummary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(AppBuildInfo.gitBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .settingsRowSeparatorAligned()
    }
}

struct CountdownEventSettingsRow: View {
    let event: CountdownEvent
    let onChangeTitle: (String) -> Void
    let onChangeDate: (Date) -> Void
    let onDelete: () -> Void
    @State private var isDatePickerPresented = false

    private var titleBinding: Binding<String> {
        Binding {
            event.title
        } set: { value in
            onChangeTitle(value)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding {
            event.date
        } set: { value in
            onChangeDate(value)
        }
    }

    var body: some View {
        SettingsTextFieldRow(
            title: AppStrings.localized("settings.countdown.eventName"),
            text: titleBinding,
            systemImage: "textformat",
            tint: .blue,
            fieldAlignment: .trailing,
            textAlignment: .trailing
        )

        Button {
            isDatePickerPresented = true
        } label: {
            HStack(spacing: 12) {
                SettingsRowIcon(systemImage: "calendar", tint: .green)

                Text(.app("settings.countdown.date"))
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .settingsRowSeparatorAligned()
        .popover(isPresented: $isDatePickerPresented) {
            datePickerPopoverContent
        }

        Button(role: .destructive, action: onDelete) {
            SettingsActionLabel(
                title: AppStrings.delete,
                systemImage: "trash",
                tint: .red
            )
        }
        .buttonStyle(.plain)
    }

    private var datePickerPopoverContent: some View {
        datePickerContent
            .padding(16)
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
            .settingsPopoverAdaptation()
    }

    private var datePickerContent: some View {
        DatePicker(
            AppStrings.localized("settings.countdown.date"),
            selection: dateBinding,
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
    }
}
