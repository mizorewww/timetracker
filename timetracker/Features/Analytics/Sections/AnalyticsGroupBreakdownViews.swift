import SwiftUI

struct AnalyticsGroupBreakdownContent: View {
    let items: [AnalyticsGroupBreakdownPoint]
    let totalSeconds: Int

    var body: some View {
        let displayedItems = Array(items.prefix(6))

        if displayedItems.isEmpty {
            EmptyStateRow(
                title: AppStrings.localized("analytics.empty.rangeTaskTime"),
                icon: "chart.pie"
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                stackedBar(displayedItems)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    ForEach(displayedItems) { item in
                        AnalyticsGroupBreakdownRow(item: item, totalSeconds: totalSeconds)
                        if item.id != displayedItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func stackedBar(_ displayedItems: [AnalyticsGroupBreakdownPoint]) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(displayedItems) { item in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: item.colorHex) ?? .blue)
                        .frame(
                            width: segmentWidth(
                                for: item,
                                count: displayedItems.count,
                                totalWidth: proxy.size.width
                            )
                        )
                }
            }
        }
        .frame(height: 16)
        .background(
            Color.secondary.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 3, style: .continuous)
        )
    }

    private func segmentWidth(
        for item: AnalyticsGroupBreakdownPoint,
        count: Int,
        totalWidth: CGFloat
    ) -> CGFloat {
        let spacing = CGFloat(max(0, count - 1)) * 3
        let availableWidth = max(0, totalWidth - spacing)
        let ratio = CGFloat(item.grossSeconds) / CGFloat(max(totalSeconds, 1))
        return max(4, availableWidth * ratio)
    }
}

private struct AnalyticsGroupBreakdownRow: View {
    let item: AnalyticsGroupBreakdownPoint
    let totalSeconds: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    identity
                    value
                }
            } else {
                HStack(spacing: 10) {
                    identity
                    Spacer(minLength: 8)
                    value
                }
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: item.colorHex) ?? .blue)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var value: some View {
        VStack(
            alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing,
            spacing: 2
        ) {
            Text(DurationFormatter.compact(item.grossSeconds))
                .font(.subheadline.monospacedDigit())
            Text("\(percentage)%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var percentage: Int {
        Int((Double(item.grossSeconds) / Double(max(totalSeconds, 1)) * 100).rounded())
    }
}
