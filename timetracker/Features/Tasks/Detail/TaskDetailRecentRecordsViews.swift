import SwiftUI

struct TaskDetailRecentRecordsCard: View {
    let records: [TaskRecentRecordPoint]

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("task.detail.recentSessions"),
            subtitle: AppStrings.localized("task.detail.recentSubtitle")
        ) {
            if records.isEmpty {
                EmptyStateRow(title: AppStrings.localized("task.records.empty"), icon: "clock")
            } else {
                let lastRecordID = records.last?.id
                VStack(spacing: 0) {
                    ForEach(records) { record in
                        TaskDetailRecentRecordRow(record: record)
                        if record.id != lastRecordID {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct TaskDetailRecentRecordRow: View {
    let record: TaskRecentRecordPoint

    var body: some View {
        HStack(spacing: 10) {
            AppRowIcon(systemImage: "clock", tint: .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(record.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.compact(record.durationSeconds))
                    .font(.subheadline.monospacedDigit())
                Text(timeRangeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
    }

    private var timeRangeText: String {
        let end = record.endedAt.map { TimeDisplayFormatter.hourMinute($0) } ?? AppStrings.localized("common.now")
        return "\(TimeDisplayFormatter.monthDayHourMinute(record.startedAt)) - \(end)"
    }
}
