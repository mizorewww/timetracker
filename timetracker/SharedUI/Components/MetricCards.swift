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

    var body: some View {
        VStack(alignment: metric.alignment.horizontalAlignment, spacing: compact ? 4 : 6) {
            HStack(spacing: 5) {
                Image(systemName: metric.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(metric.tint)
                Text(metric.title)
                    .font((compact ? Font.caption2 : Font.caption).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)

            Text(metric.value)
                .font(.system(size: compact ? 20 : 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)

            Text(metric.trendText)
                .font(.caption2)
                .foregroundStyle(metric.trendColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)
        }
        .frame(maxWidth: .infinity, alignment: metric.alignment.frameAlignment)
        .padding(.horizontal, compact ? 4 : 10)
    }
}

struct AnalyticsMetric: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

struct AnalyticsChartCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(title: title, subtitle: subtitle)
            content
        }
        .appCard()
    }
}
