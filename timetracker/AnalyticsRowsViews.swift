import SwiftUI

struct ScreenTimeBreakdownCard: View {
    let tasks: [TaskAnalyticsPoint]
    let totalSeconds: Int

    private var visibleTasks: [TaskAnalyticsPoint] {
        Array(tasks.prefix(6))
    }

    var body: some View {
        AnalyticsChartCard(title: AppStrings.localized("analytics.screenTime.title"), subtitle: AppStrings.localized("analytics.screenTime.subtitle")) {
            VStack(alignment: .leading, spacing: 14) {
                if tasks.isEmpty {
                    EmptyStateRow(title: AppStrings.localized("analytics.empty.todayTaskTime"), icon: "hourglass")
                } else {
                    screenTimeBar

                    VStack(spacing: 0) {
                        ForEach(visibleTasks) { task in
                            ScreenTimeTaskRow(task: task, totalSeconds: totalSeconds)
                            if task.id != visibleTasks.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var screenTimeBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(visibleTasks) { task in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: task.colorHex) ?? .blue)
                        .frame(width: segmentWidth(for: task, totalWidth: proxy.size.width))
                }
                if tasks.count > visibleTasks.count {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 20)
                }
            }
        }
        .frame(height: 16)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func segmentWidth(for task: TaskAnalyticsPoint, totalWidth: CGFloat) -> CGFloat {
        let ratio = CGFloat(task.grossSeconds) / CGFloat(max(totalSeconds, 1))
        return max(10, totalWidth * ratio)
    }
}

struct ScreenTimeTaskRow: View {
    let task: TaskAnalyticsPoint
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hex: task.colorHex) ?? .blue)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(task.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.compact(task.grossSeconds))
                    .font(.subheadline.monospacedDigit())
                Text("\(Int((Double(task.grossSeconds) / Double(max(totalSeconds, 1))) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct AnalyticsTaskRow: View {
    let task: TaskAnalyticsPoint
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: task.colorHex) ?? .blue)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                Text(task.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(DurationFormatter.compact(task.grossSeconds))
                    .font(.subheadline.monospacedDigit())
                Text("\(Int(Double(task.grossSeconds) / Double(totalSeconds) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

struct OverlapRow: View {
    let overlap: OverlapAnalyticsPoint

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.2.swap")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(overlap.firstTitle) + \(overlap.secondTitle)")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(timeRangeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(DurationFormatter.compact(overlap.durationSeconds))
                .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 10)
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: overlap.start)) - \(endFormatter.string(from: overlap.end))"
    }
}
