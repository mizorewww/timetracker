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

struct AnalyticsGroupBreakdownPresentation {
    let items: [AnalyticsGroupBreakdownDisplayItem]
    let totalSeconds: Int

    static func make(
        items: [AnalyticsGroupBreakdownPoint],
        reportedTotalSeconds: Int,
        maximumItemCount: Int = 6,
        otherTitle: String,
        otherSubtitle: String
    ) -> AnalyticsGroupBreakdownPresentation {
        let candidates = items.compactMap { item -> AnalyticsGroupBreakdownDisplayItem? in
            guard item.grossSeconds > 0 else { return nil }
            return AnalyticsGroupBreakdownDisplayItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                iconName: item.iconName,
                colorHex: item.colorHex,
                grossSeconds: item.grossSeconds
            )
        }
        .sorted {
            if $0.grossSeconds != $1.grossSeconds {
                return $0.grossSeconds > $1.grossSeconds
            }
            return $0.id < $1.id
        }

        let accountedSeconds = candidates.reduce(0) { $0 + $1.grossSeconds }
        let effectiveTotal = max(max(0, reportedTotalSeconds), accountedSeconds)
        var otherSeconds = effectiveTotal - accountedSeconds
        let itemLimit = max(1, maximumItemCount)
        let needsOtherItem = candidates.count + (otherSeconds > 0 ? 1 : 0) > itemLimit
        let visibleCount = needsOtherItem ? max(0, itemLimit - 1) : candidates.count
        var displayedItems = Array(candidates.prefix(visibleCount))

        if needsOtherItem {
            otherSeconds += candidates.dropFirst(visibleCount).reduce(0) {
                $0 + $1.grossSeconds
            }
        }
        if otherSeconds > 0 {
            displayedItems.append(
                AnalyticsGroupBreakdownDisplayItem(
                    id: "analytics-group-breakdown-other",
                    title: otherTitle,
                    subtitle: otherSubtitle,
                    iconName: "ellipsis.circle",
                    colorHex: "8E8E93",
                    grossSeconds: otherSeconds
                )
            )
        }

        return AnalyticsGroupBreakdownPresentation(
            items: displayedItems,
            totalSeconds: effectiveTotal
        )
    }
}

struct AnalyticsGroupBreakdownDisplayItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let iconName: String
    let colorHex: String
    let grossSeconds: Int
}

struct AnalyticsGroupBarLayoutItem: Identifiable, Equatable {
    let id: String
    let width: CGFloat
}

enum AnalyticsGroupBarLayoutEngine {
    static func layout(
        items: [AnalyticsGroupBreakdownDisplayItem],
        totalSeconds: Int,
        availableWidth: CGFloat,
        spacing: CGFloat = 3,
        minimumSegmentWidth: CGFloat = 4
    ) -> [AnalyticsGroupBarLayoutItem] {
        guard !items.isEmpty, availableWidth > 0 else { return [] }

        let totalSpacing = CGFloat(max(0, items.count - 1)) * max(0, spacing)
        let contentWidth = max(0, availableWidth - totalSpacing)
        guard contentWidth > 0 else { return [] }

        let effectiveMinimum = min(
            max(0, minimumSegmentWidth),
            contentWidth / CGFloat(items.count)
        )
        let itemTotal = items.reduce(0) { $0 + $1.grossSeconds }
        let denominator = CGFloat(max(max(totalSeconds, itemTotal), 1))
        var widths = items.map {
            contentWidth * CGFloat($0.grossSeconds) / denominator
        }

        var deficit: CGFloat = 0
        for index in widths.indices where widths[index] < effectiveMinimum {
            deficit += effectiveMinimum - widths[index]
            widths[index] = effectiveMinimum
        }

        while deficit > 0.0001,
              let donorIndex = widths.indices
                .filter({ widths[$0] > effectiveMinimum })
                .max(by: { widths[$0] < widths[$1] }) {
            let donation = min(deficit, widths[donorIndex] - effectiveMinimum)
            widths[donorIndex] -= donation
            deficit -= donation
        }

        let drift = contentWidth - widths.reduce(0, +)
        if let widestIndex = widths.indices.max(by: { widths[$0] < widths[$1] }) {
            widths[widestIndex] = max(0, widths[widestIndex] + drift)
        }

        return zip(items, widths).map { item, width in
            AnalyticsGroupBarLayoutItem(id: item.id, width: width)
        }
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
