import SwiftUI

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
                    SettingsUnavailableRow(
                        title: AppStrings.localized("settings.countdown.empty"),
                        message: AppStrings.localized("settings.countdown.emptyDescription"),
                        systemImage: "calendar.badge.exclamationmark"
                    )
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
                .accessibilityIdentifier("settings.countdown.add")
            }
        }
    }
}
