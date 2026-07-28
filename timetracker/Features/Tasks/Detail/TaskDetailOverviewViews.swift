import SwiftUI

struct TaskDetailOverviewSection: View {
    let snapshot: TaskAnalyticsSnapshot
    let periodTitle: String?

    var body: some View {
        Section {
            TaskDetailValueRow(
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(snapshot.overview.grossSeconds),
                systemImage: "square.stack.3d.up",
                tint: AppColors.grossTime,
                accessibilityIdentifier: "task.detail.summary.gross"
            )
            TaskDetailValueRow(
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(snapshot.overview.wallSeconds),
                systemImage: "timeline.selection",
                tint: AppColors.wallTime,
                accessibilityIdentifier: "task.detail.summary.wall"
            )
            if snapshot.source == .tracked {
                TaskDetailValueRow(
                    title: AppStrings.localized("task.detail.direct"),
                    value: DurationFormatter.compact(snapshot.directSeconds),
                    systemImage: "smallcircle.filled.circle",
                    tint: .indigo,
                    accessibilityIdentifier: "task.detail.summary.direct"
                )
                TaskDetailValueRow(
                    title: AppStrings.localized("task.detail.children"),
                    value: DurationFormatter.compact(snapshot.descendantSeconds),
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tint: .teal,
                    accessibilityIdentifier: "task.detail.summary.children"
                )
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(AppStrings.localized("analytics.summary.title"))
                    .accessibilityIdentifier("task.detail.summary")
                if let periodTitle {
                    Spacer(minLength: 8)
                    Text(periodTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier(
                            "task.detail.summary.period"
                        )
                }
            }
        }
    }
}

struct TaskDetailValueRow: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let accessibilityIdentifier: String
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
        .accessibilityIdentifier(accessibilityIdentifier)
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

    var body: some View {
        if let rollup {
            Section {
                if let displayedTask, displayedTask.id != task.id {
                    Text(String(format: AppStrings.localized("forecast.showingChildFormat"), displayedTask.title))
                        .font(childExplanationFont)
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
                    .font(reasonFont)
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

    private var childExplanationFont: Font {
        .body
    }

    private var reasonFont: Font {
        .body
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
