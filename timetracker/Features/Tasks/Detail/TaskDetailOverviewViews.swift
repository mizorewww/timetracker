import SwiftUI

struct TaskDetailOverviewSection: View {
    let snapshot: TaskAnalyticsSnapshot

    var body: some View {
        Section(AppStrings.localized("analytics.summary.title")) {
            TaskDetailValueRow(
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(snapshot.overview.grossSeconds),
                systemImage: "square.stack.3d.up",
                tint: .blue
            )
            TaskDetailValueRow(
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(snapshot.overview.wallSeconds),
                systemImage: "timeline.selection",
                tint: .green
            )
            TaskDetailValueRow(
                title: AppStrings.localized("task.detail.direct"),
                value: DurationFormatter.compact(snapshot.directSeconds),
                systemImage: "smallcircle.filled.circle",
                tint: .indigo
            )
            TaskDetailValueRow(
                title: AppStrings.localized("task.detail.children"),
                value: DurationFormatter.compact(snapshot.descendantSeconds),
                systemImage: "point.3.connected.trianglepath.dotted",
                tint: .teal
            )
        }
        .accessibilityIdentifier("task.detail.summary")
    }
}

struct TaskDetailValueRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        AppRowIcon(systemImage: systemImage, tint: tint)
                        Text(title)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(value)
                        .font(.headline.monospacedDigit())
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 12) {
                    AppRowIcon(systemImage: systemImage, tint: tint)
                    Text(title)
                    Spacer(minLength: 12)
                    Text(value)
                        .font(.headline.monospacedDigit())
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TaskDetailForecastSection: View {
    let store: TimeTrackerStore
    let task: TaskNode

    private var displayItem: ForecastDisplayItem? {
        store.forecastDisplayItem(for: task.id)
    }

    private var displayedTask: TaskNode? {
        displayItem.flatMap { store.task(for: $0.taskID) }
    }

    private var rollup: TaskRollup? {
        displayItem?.rollup ?? store.rollup(for: task.id)
    }

    @ViewBuilder
    var body: some View {
        if let rollup {
            Section {
                if let displayedTask, displayedTask.id != task.id {
                    Text(String(format: AppStrings.localized("forecast.showingChildFormat"), displayedTask.title))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TaskDetailForecastValue(
                    title: AppStrings.localized("forecast.worked"),
                    value: DurationFormatter.compact(rollup.workedSeconds)
                )
                if rollup.isDisplayableForecast {
                    TaskDetailForecastValue(
                        title: AppStrings.localized("forecast.remaining"),
                        value: rollup.remainingDisplayText
                    )
                    TaskDetailForecastValue(
                        title: AppStrings.localized("forecast.projectedDays"),
                        value: rollup.projectedDaysDisplayText
                    )
                    TaskDetailForecastValue(
                        title: AppStrings.localized("forecast.confidence"),
                        value: rollup.confidence.displayName
                    )
                }
                Text(rollup.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text(AppStrings.localized("forecast.panel.title"))
                    Spacer()
                    ForecastInfoButton()
                }
            }
            .accessibilityIdentifier("task.detail.forecast")
        }
    }
}

private struct TaskDetailForecastValue: View {
    let title: String
    let value: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.headline.monospacedDigit())
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
            } else {
                LabeledContent(title) {
                    Text(value)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
