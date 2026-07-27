import SwiftUI

struct AnalyticsGroupBreakdownContent: View {
    let items: [AnalyticsGroupBreakdownPoint]
    let totalSeconds: Int

    private var presentation: AnalyticsGroupBreakdownPresentation {
        AnalyticsGroupBreakdownPresentation.make(
            items: items,
            reportedTotalSeconds: totalSeconds,
            otherTitle: AppStrings.localized("analytics.group.other.title"),
            otherSubtitle: AppStrings.localized("analytics.group.other.subtitle")
        )
    }

    var body: some View {
        let distribution = presentation
        let displayedItems = distribution.items

        if displayedItems.isEmpty {
            EmptyStateRow(
                title: AppStrings.localized("analytics.empty.rangeTaskTime"),
                icon: "chart.pie"
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                stackedBar(
                    displayedItems,
                    totalSeconds: distribution.totalSeconds
                )
                .accessibilityHidden(true)

                VStack(spacing: 0) {
                    ForEach(displayedItems) { item in
                        AnalyticsGroupBreakdownRow(
                            item: item,
                            totalSeconds: distribution.totalSeconds
                        )
                        if item.id != displayedItems.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func stackedBar(
        _ displayedItems: [AnalyticsGroupBreakdownDisplayItem],
        totalSeconds: Int
    ) -> some View {
        GeometryReader { proxy in
            let layout = AnalyticsGroupBarLayoutEngine.layout(
                items: displayedItems,
                totalSeconds: totalSeconds,
                availableWidth: proxy.size.width
            )
            let itemByID = Dictionary(uniqueKeysWithValues: displayedItems.map { ($0.id, $0) })

            HStack(spacing: 3) {
                ForEach(layout) { segment in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: itemByID[segment.id]?.colorHex ?? "0A84FF") ?? .blue)
                        .frame(width: segment.width)
                }
            }
        }
        .frame(height: 16)
        .background(
            Color.secondary.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 3, style: .continuous)
        )
    }
}

private struct AnalyticsGroupBreakdownRow: View {
    let item: AnalyticsGroupBreakdownDisplayItem
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
                    .font(primaryFont.weight(.medium))
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
                .font(primaryFont.monospacedDigit())
            Text("\(percentage)%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var percentage: Int {
        Int((Double(item.grossSeconds) / Double(max(totalSeconds, 1)) * 100).rounded())
    }

    private var primaryFont: Font {
        #if os(macOS)
        .body
        #else
        .subheadline
        #endif
    }
}
