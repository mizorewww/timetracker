import SwiftUI

struct TodayHeatmapSettingsSection: View {
    let store: TimeTrackerStore
    let onChangePeriod: (ActivityHeatmapPeriod) -> Void
    let onChangeSelection: ([UUID]) -> Void

    var body: some View {
        Section {
            Picker(selection: periodBinding) {
                ForEach(ActivityHeatmapPeriod.allCases) { period in
                    Text(.app(period.settingsLocalizationKey))
                        .tag(period)
                        .accessibilityIdentifier(
                            "settings.todayHeatmap.period.\(period.rawValue)"
                        )
                }
            } label: {
                SettingsRowLabel(
                    title: AppStrings.localized("heatmap.settings.period"),
                    systemImage: "calendar",
                    tint: .green
                )
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("settings.todayHeatmap.period")

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
        store.todayHeatmapSelectedTaskIDs
    }

    private var periodBinding: Binding<ActivityHeatmapPeriod> {
        Binding(
            get: { store.preferences.todayHeatmapPeriod },
            set: { period in
                guard period != store.preferences.todayHeatmapPeriod else {
                    return
                }
                onChangePeriod(period)
            }
        )
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

private extension ActivityHeatmapPeriod {
    var settingsLocalizationKey: String {
        switch self {
        case .oneMonth:
            "heatmap.settings.period.oneMonth"
        case .threeMonths:
            "heatmap.settings.period.threeMonths"
        case .sixMonths:
            "heatmap.settings.period.sixMonths"
        case .oneYear:
            "heatmap.settings.period.oneYear"
        }
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
        store.todayHeatmapSelectedTaskIDs
    }

    private var hiddenSelectedTaskIDs: Set<UUID> {
        let selectableTaskIDs = store.todayHeatmapSelectableTaskIDs
        return Set(selectedTaskIDs.filter { taskID in
            guard let task = store.task(for: taskID) else { return true }
            return store.isTaskVisible(task) == false ||
                selectableTaskIDs.contains(taskID) == false
        })
    }

    @ViewBuilder
    private var hiddenSelectionRecovery: some View {
        if hiddenSelectedTaskIDs.isEmpty == false {
            HStack(spacing: 12) {
                Label(
                    String.localizedStringWithFormat(
                        AppStrings.localized("heatmap.picker.hiddenSelectionCount"),
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
                .accessibilityIdentifier("settings.todayHeatmap.taskPicker.removeHidden")
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
            AppPreferenceValueSanitizer.maximumTodayHeatmapTaskCount
        else {
            return
        }
        onChangeSelection(updated)
    }
}
