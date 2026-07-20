import SwiftUI

struct TodayHeatmapSettingsSection: View {
    let store: TimeTrackerStore
    let onChangeSelection: ([UUID]) -> Void

    var body: some View {
        Section {
            NavigationLink {
                TodayHeatmapTaskSelectionView(
                    store: store,
                    onChangeSelection: onChangeSelection
                )
            } label: {
                SettingsValueRow(
                    title: AppStrings.localized("heatmap.settings.tasks"),
                    value: selectionSummary,
                    systemImage: "square.grid.3x3.fill",
                    tint: .green
                )
            }
            .accessibilityIdentifier("settings.todayHeatmap.tasks")
        } header: {
            SettingsHeader(
                symbol: "square.grid.3x3.fill",
                title: AppStrings.localized("heatmap.settings.title")
            )
        } footer: {
            Text(.app("heatmap.settings.footer"))
        }
    }

    private var selectedTaskIDs: [UUID] {
        store.preferences.todayHeatmapTaskIDs
    }

    private var selectionSummary: String {
        guard selectedTaskIDs.isEmpty == false else {
            return AppStrings.localized("heatmap.settings.off")
        }
        return String.localizedStringWithFormat(
            AppStrings.localized("heatmap.settings.taskCount"),
            selectedTaskIDs.count
        )
    }
}

private struct TodayHeatmapTaskSelectionView: View {
    let store: TimeTrackerStore
    let onChangeSelection: ([UUID]) -> Void

    var body: some View {
        TaskHierarchyPicker(
            store: store,
            mode: .multipleSelection(
                selectedTaskIDs: Set(selectedTaskIDs),
                context: .todayHeatmap,
                maximumSelectionCount:
                    AppPreferenceValueSanitizer.maximumTodayHeatmapTaskCount
            ),
            onDismiss: {},
            onSelect: toggleSelection
        )
        .safeAreaInset(edge: .bottom) {
            hiddenSelectionRecovery
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(AppStrings.localized("heatmap.picker.clear")) {
                    onChangeSelection([])
                }
                .disabled(selectedTaskIDs.isEmpty)
                .accessibilityIdentifier("settings.todayHeatmap.taskPicker.clear")
            }
        }
    }

    private var selectedTaskIDs: [UUID] {
        store.preferences.todayHeatmapTaskIDs
    }

    private var hiddenSelectedTaskIDs: Set<UUID> {
        Set(selectedTaskIDs.filter { taskID in
            guard let task = store.task(for: taskID) else { return true }
            return store.isTaskVisible(task) == false
        })
    }

    @ViewBuilder
    private var hiddenSelectionRecovery: some View {
        if hiddenSelectedTaskIDs.isEmpty == false {
            HStack(spacing: 12) {
                Label(
                    String.localizedStringWithFormat(
                        AppStrings.localized(
                            "heatmap.picker.hiddenSelectionCount"
                        ),
                        hiddenSelectedTaskIDs.count
                    ),
                    systemImage: "eye.slash"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button(AppStrings.localized("heatmap.picker.removeHidden")) {
                    onChangeSelection(
                        OrderedTaskIDSelectionMutation.removing(
                            hiddenSelectedTaskIDs,
                            from: selectedTaskIDs
                        )
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(
                    "settings.todayHeatmap.taskPicker.removeHidden"
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func toggleSelection(_ taskID: UUID) {
        let updated = OrderedTaskIDSelectionMutation.toggling(
            taskID,
            in: selectedTaskIDs
        )
        guard updated.count <=
                AppPreferenceValueSanitizer.maximumTodayHeatmapTaskCount else {
            return
        }
        onChangeSelection(updated)
    }
}
