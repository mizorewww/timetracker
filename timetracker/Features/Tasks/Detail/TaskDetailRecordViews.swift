import SwiftUI

struct TaskDetailRecordsSection: View {
    let records: [TaskRecentRecordPoint]

    var body: some View {
        Section {
            if records.isEmpty {
                EmptyStateRow(title: AppStrings.localized("task.records.empty"), icon: "clock")
            } else {
                ForEach(records) { record in
                    TaskDetailRecentRecordRow(record: record)
                }
            }
        } header: {
            Text(AppStrings.localized("task.detail.recentSessions"))
        } footer: {
            Text(.app("task.detail.recentSubtitle"))
        }
    }
}

private struct TaskDetailRecentRecordRow: View {
    let record: TaskRecentRecordPoint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    recordIdentity
                    recordTiming
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 10) {
                    recordIdentity
                    Spacer(minLength: 8)
                    recordTiming
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var recordIdentity: some View {
        HStack(alignment: .top, spacing: 10) {
            AppRowIcon(systemImage: "clock", tint: .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(record.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordTiming: some View {
        let display = trackedTimeDisplay
        return VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text(DurationFormatter.compact(display.elapsedSeconds))
                .font(.subheadline.monospacedDigit())
            Text(timeRangeText(display: display))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func timeRangeText(display: TrackedTimeDisplaySnapshot) -> String {
        let end = display.usesCurrentEndLabel
            ? AppStrings.localized("common.now")
            : TimeDisplayFormatter.hourMinute(display.end)
        return "\(TimeDisplayFormatter.monthDayHourMinute(display.start)) - \(end)"
    }

    private var trackedTimeDisplay: TrackedTimeDisplaySnapshot {
        TrackedTimeDisplaySnapshot(
            startedAt: record.startedAt,
            endedAt: record.endedAt,
            now: Date()
        )
    }
}
