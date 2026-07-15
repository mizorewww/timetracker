import SwiftUI

struct MetricSummaryItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let iconName: String
    let tint: Color
    let trendText: String
    let trendColor: Color
    let alignment: MetricTextAlignment
}

enum MetricTextAlignment {
    case leading
    case center
    case trailing

    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

struct MetricCell: View {
    let metric: MetricSummaryItem
    var compact: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: metric.alignment.horizontalAlignment, spacing: compact ? 4 : 6) {
            HStack(spacing: 5) {
                Image(systemName: metric.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(metric.tint)
                    .accessibilityHidden(true)
                Text(metric.title)
                    .font((compact ? Font.caption2 : Font.caption).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)

            Text(metric.value)
                .font((compact ? Font.title3 : Font.title2).weight(.semibold).monospacedDigit())
                .monospacedDigit()
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)

            Text(metric.trendText)
                .font(.caption2)
                .foregroundStyle(metric.trendColor)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)
        }
        .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)
        .padding(.horizontal, compact ? 4 : 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue("\(metric.value), \(metric.trendText)")
    }
}
