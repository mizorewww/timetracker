import SwiftUI

struct TaskDetailHeatmapTrackingSection: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let colorHex: String

    var body: some View {
        Section {
            Toggle(isOn: trackingBinding) {
                Label(
                    AppStrings.localized("task.detail.heatmap.toggle"),
                    systemImage: "square.grid.3x3.fill"
                )
            }
            .disabled(isAtSelectionLimit && isTracking == false)
            .accessibilityIdentifier("task.detail.heatmapTracking")

            if isTracking {
                LabeledContent(
                    AppStrings.localized("task.detail.heatmap.palette")
                ) {
                    ActivityHeatmapPalettePreview(colorHex: colorHex)
                }
                .accessibilityIdentifier("task.detail.heatmapPalette")
            }
        } header: {
            Text(.app("task.detail.heatmap.title"))
        } footer: {
            Text(
                .app(
                    isAtSelectionLimit && isTracking == false
                        ? "task.detail.heatmap.limitReached"
                        : "task.detail.heatmap.footer"
                )
            )
        }
    }

    private var isTracking: Bool {
        store.preferences.todayHeatmapTaskIDs.contains(task.id)
    }

    private var isAtSelectionLimit: Bool {
        store.preferences.todayHeatmapTaskIDs.count >=
            AppPreferenceValueSanitizer.maximumTodayHeatmapTaskCount
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
