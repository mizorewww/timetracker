import CoreGraphics

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
              .max(by: { widths[$0] < widths[$1] })
        {
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
