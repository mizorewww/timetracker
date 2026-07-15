import SwiftUI

struct AboutAppSummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    appIcon
                    appDetails
                }
            } else {
                HStack(spacing: 14) {
                    appIcon
                    appDetails
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 6)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
        .settingsRowSeparatorAligned()
    }

    private var appIcon: some View {
        AppIconImage()
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)
    }

    private var appDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppBuildInfo.displayName)
                .font(.headline)
            Text(String(format: AppStrings.localized("settings.about.versionFormat"), AppBuildInfo.versionSummary))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(AppBuildInfo.gitBranch)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CountdownEventSettingsRow: View {
    let event: CountdownEvent
    let onChangeTitle: (String) -> Void
    let onChangeDate: (Date) -> Void
    let onDelete: () -> Void
    @State private var isDatePickerPresented = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            textAlignment: .trailing,
            usesSentenceCapitalization: true
        )

        Button {
            isDatePickerPresented = true
        } label: {
            countdownDateLabel
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
            .settingsPopoverContentFrame(idealWidth: 360)
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

    @ViewBuilder
    private var countdownDateLabel: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    SettingsRowIcon(systemImage: "calendar", tint: .green)
                    Text(.app("settings.countdown.date"))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
            }
        } else {
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
                    .accessibilityHidden(true)
            }
        }
    }
}
