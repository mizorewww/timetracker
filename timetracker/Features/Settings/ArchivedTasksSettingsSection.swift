import SwiftUI

struct ArchivedTasksSettingsSection: View {
    let store: TimeTrackerStore
    let onUnarchive: (TaskNode) -> Void

    var body: some View {
        let archivedTasks = store.archivedTasks

        Section {
            if archivedTasks.isEmpty {
                archivedTasksEmptyState
            } else {
                ForEach(archivedTasks) { task in
                    ArchivedTaskSettingsRow(
                        presentation: store.taskIdentityPresentation(for: task),
                        canUnarchive: store.hasArchivedAncestor(for: task) == false,
                        unarchive: { onUnarchive(task) }
                    )
                }
            }
        } header: {
            SettingsHeader(
                symbol: "archivebox",
                title: AppStrings.localized("settings.archivedTasks.title")
            )
        } footer: {
            Text(.app("settings.archivedTasks.footer"))
        }
    }

    private var archivedTasksEmptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsRowIcon(systemImage: "archivebox", tint: .gray)
            VStack(alignment: .leading, spacing: 3) {
                Text(.app("settings.archivedTasks.empty.title"))
                    .foregroundStyle(.primary)
                Text(.app("settings.archivedTasks.empty.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .settingsRowSeparatorAligned()
        .accessibilityIdentifier("settings.archivedTasks.empty")
    }
}

private struct ArchivedTaskSettingsRow: View {
    let presentation: TaskIdentityPresentation
    let canUnarchive: Bool
    let unarchive: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TaskSummaryRow(
                    presentation: presentation,
                    context: .standard,
                    iconSize: 28
                )

                if canUnarchive == false {
                    Label(
                        AppStrings.localized("settings.archivedTasks.parentFirst"),
                        systemImage: "arrow.turn.up.left"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: unarchive) {
                Label(AppStrings.localized("task.action.unarchive"), systemImage: "archivebox")
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(minHeight: actionTargetSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .fixedSize(horizontal: true, vertical: true)
            .disabled(canUnarchive == false)
            .accessibilityIdentifier(
                "settings.archivedTasks.unarchive.\(presentation.id.uuidString)"
            )
            .accessibilityHint(
                Text(
                    .app(
                        canUnarchive
                            ? "settings.archivedTasks.unarchive.hint"
                            : "settings.archivedTasks.parentFirst"
                    )
                )
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
        .opacity(canUnarchive ? 1 : 0.55)
        .settingsRowSeparatorAligned()
    }

    private var actionTargetSize: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }
}
