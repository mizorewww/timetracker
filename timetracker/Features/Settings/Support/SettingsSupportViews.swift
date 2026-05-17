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

        DatePicker(
            selection: dateBinding,
            displayedComponents: .date
        ) {
            SettingsRowLabel(
                title: AppStrings.localized("settings.countdown.date"),
                systemImage: "calendar",
                tint: .green
            )
        }
        .datePickerStyle(.compact)
        .settingsRowSeparatorAligned()
        .accessibilityIdentifier("settings.countdown.date")

        Button(role: .destructive, action: onDelete) {
            SettingsActionLabel(
                title: AppStrings.delete,
                systemImage: "trash",
                tint: .red
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.countdown.delete")
    }
}
