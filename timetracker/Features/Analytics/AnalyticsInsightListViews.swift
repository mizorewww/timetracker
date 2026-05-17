import SwiftUI

struct AnalyticsInsightList: View {
    let insights: [AnalyticsInsight]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(insights) { insight in
                AnalyticsInsightRow(insight: insight)
                if insight.id != insights.last?.id {
                    Divider()
                }
            }
        }
    }
}

private struct AnalyticsInsightRow: View {
    let insight: AnalyticsInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsRowIcon(systemImage: iconName, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline.weight(.medium))
                Text(insight.value)
                    .font(.headline.monospacedDigit())
                Text(insight.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var iconName: String {
        switch insight.severity {
        case .positive:
            return "checkmark.seal"
        case .neutral:
            return "target"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "exclamationmark.octagon"
        }
    }

    private var tint: Color {
        switch insight.severity {
        case .positive:
            return .green
        case .neutral:
            return .blue
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}
