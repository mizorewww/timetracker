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
        VStack(alignment: .leading, spacing: 10) {
            SettingsTextFieldRow(
                title: AppStrings.localized("settings.countdown.eventName"),
                text: titleBinding,
                systemImage: "textformat",
                tint: .blue
            )
            HStack {
                DatePicker(selection: dateBinding, displayedComponents: .date) {
                    SettingsRowLabel(
                        title: AppStrings.localized("settings.countdown.date"),
                        systemImage: "calendar",
                        tint: .green
                    )
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
