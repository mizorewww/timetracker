import SwiftUI

struct CountdownSettingsSection: View {
    let events: [CountdownEvent]
    let onChangeTitle: (CountdownEvent, String) -> Bool
    let onChangeDate: (CountdownEvent, Date) -> Void
    let onDelete: (CountdownEvent) -> Void
    let onAdd: () -> Void
    @State private var pendingDeletionEventID: UUID?

    var body: some View {
        Group {
            Section {
                if events.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        SettingsRowIcon(systemImage: "calendar.badge.exclamationmark", tint: .gray)
                        Text(.app("settings.countdown.empty"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .settingsRowSeparatorAligned()
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
                            pendingDeletionEventID = event.id
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
            }
        }
        .confirmationDialog(
            AppStrings.localized("settings.countdown.delete.confirm.title"),
            isPresented: Binding(
                get: { pendingDeletionEventID != nil },
                set: { if !$0 { pendingDeletionEventID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete, role: .destructive) {
                guard let pendingDeletionEventID,
                      let event = events.first(where: { $0.id == pendingDeletionEventID }) else { return }
                onDelete(event)
                self.pendingDeletionEventID = nil
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("settings.countdown.delete.confirm.message"))
        }
    }
}
