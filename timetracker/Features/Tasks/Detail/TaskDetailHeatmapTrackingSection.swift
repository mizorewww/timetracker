import SwiftUI

struct TaskDetailHeatmapTrackingSection: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let colorHex: String

    var body: some View {
        Section {
            Toggle(isOn: trackingBinding) {
                Label(
                    AppStrings.localized(
                        isRecurringOccurrence
                            ? "task.detail.heatmap.recurringToggle"
                            : "task.detail.heatmap.toggle"
                    ),
                    systemImage: "square.grid.3x3.fill"
                )
            }
            .disabled(
                isHeatmapAvailable == false ||
                    (isAtSelectionLimit && isTracking == false)
            )
            .accessibilityIdentifier("task.detail.heatmapTracking")

            if isTracking {
                LabeledContent(
                    AppStrings.localized("task.detail.heatmap.palette")
                ) {
                    ActivityHeatmapPalettePreview(
                        colorHex: heatmapOwnerColorHex
                    )
                }
                .accessibilityIdentifier("task.detail.heatmapPalette")
            }
        } header: {
            Text(.app("task.detail.heatmap.title"))
        } footer: {
            Text(.app(footerLocalizationKey))
        }
    }

    private var heatmapOwnerTaskID: UUID? {
        store.todayHeatmapOwnerTaskID(for: task.id)
    }

    private var isRecurringOccurrence: Bool {
        guard let heatmapOwnerTaskID else { return false }
        return heatmapOwnerTaskID != task.id
    }

    private var isHeatmapAvailable: Bool {
        guard let heatmapOwnerTaskID else { return false }
        return store.todayHeatmapSelectableTaskIDs.contains(
            heatmapOwnerTaskID
        )
    }

    private var isTracking: Bool {
        guard let heatmapOwnerTaskID else { return false }
        return store.todayHeatmapSelectedTaskIDs.contains(
            heatmapOwnerTaskID
        )
    }

    private var isAtSelectionLimit: Bool {
        store.todayHeatmapSelectedTaskIDs.count >=
            AppPreferenceValueSanitizer.maximumTodayHeatmapTaskCount
    }

    private var heatmapOwnerColorHex: String {
        guard let heatmapOwnerTaskID else { return colorHex }
        return store.task(for: heatmapOwnerTaskID)?.colorHex ?? colorHex
    }

    private var footerLocalizationKey: String {
        if isHeatmapAvailable == false {
            return "task.detail.heatmap.unavailable"
        }
        if isAtSelectionLimit && isTracking == false {
            return "task.detail.heatmap.limitReached"
        }
        return isRecurringOccurrence
            ? "task.detail.heatmap.recurringFooter"
            : "task.detail.heatmap.footer"
    }

    private var trackingBinding: Binding<Bool> {
        Binding {
            isTracking
        } set: { isEnabled in
            _ = store.setTodayHeatmapTrackingEnabled(
                isEnabled,
                for: task.id
            )
        }
    }
}
