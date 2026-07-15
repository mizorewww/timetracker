import SwiftUI

struct TaskForecastSummarySection: View {
    let store: TimeTrackerStore
    let forecasts: [ForecastDisplayItem]

    var body: some View {
        let rows = forecasts.compactMap { item in
            store.task(for: item.taskID).map {
                ForecastPresentationRow(item: item, task: $0)
            }
        }

        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: AppStrings.localized("forecast.today.title"))
                    ForecastInfoButton()
                }

                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        ForecastSummaryRow(
                            store: store,
                            task: row.task,
                            rollup: row.item.rollup
                        )
                        if row.id != rows.last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
                .appCard(padding: 0)
            }
            .accessibilityIdentifier("home.forecasts")
        }
    }
}

private struct ForecastPresentationRow: Identifiable {
    let item: ForecastDisplayItem
    let task: TaskNode

    var id: UUID { item.taskID }
}

struct ForecastSummaryRow: View {
    let store: TimeTrackerStore
    let task: TaskNode
    let rollup: TaskRollup
    var openTaskDetail: ((UUID) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            if let openTaskDetail {
                openTaskDetail(task.id)
            } else {
                store.openTaskDetail(task.id)
            }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityContent
                } else {
                    regularContent
                }
            }
            .contentShape(Rectangle())
            .padding(14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.title)
        .accessibilityValue(
            String.localizedStringWithFormat(
                AppStrings.localized("forecast.accessibilityValueFormat"),
                remainingText,
                daysText,
                rollup.reason
            )
        )
        .accessibilityHint(AppStrings.localized("tasks.openDetail"))
    }

    private var regularContent: some View {
        HStack(alignment: .top, spacing: 12) {
            TaskIcon(task: task, size: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    checklistProgressLabel
                }
                Text(store.path(for: task))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                progressBar
                supportingDetails(allowsWrapping: false)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                remainingLabel
                daysLabel
            }
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                TaskIcon(task: task, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(store.path(for: task))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            checklistProgressLabel
            progressBar
            remainingLabel
            daysLabel
            supportingDetails(allowsWrapping: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var checklistProgressLabel: some View {
        if rollup.checklistProgress.totalCount > 0 {
            Text(rollup.checklistProgress.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
        }
    }

    private var progressBar: some View {
        ProgressView(value: rollup.completionFraction)
            .tint(Color(hex: task.colorHex) ?? .blue)
    }

    private var remainingLabel: some View {
        Text(remainingText)
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var daysLabel: some View {
        Text(daysText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func supportingDetails(allowsWrapping: Bool) -> some View {
        if let sourceLabel = rollup.forecastSourceLabel {
            Text(sourceLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(allowsWrapping ? nil : 1)
                .fixedSize(horizontal: false, vertical: allowsWrapping)
        }
        Text(rollup.reason)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(allowsWrapping ? nil : 2)
            .fixedSize(horizontal: false, vertical: allowsWrapping)
        if let paceText = rollup.historicalPaceDisplayText {
            Text(paceText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(allowsWrapping ? nil : 1)
                .fixedSize(horizontal: false, vertical: allowsWrapping)
        }
    }

    private var remainingText: String {
        rollup.remainingDisplayText
    }

    private var daysText: String {
        rollup.projectedDays == nil ? rollup.confidence.displayName : rollup.projectedDaysDisplayText
    }
}
