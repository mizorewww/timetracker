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
