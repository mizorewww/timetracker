import SwiftUI

struct AnalyticsGlossaryList: View {
    var body: some View {
        VStack(spacing: 0) {
            AnalyticsGlossaryRow(
                title: AppStrings.grossTime,
                bodyText: AppStrings.localized("analytics.glossary.gross")
            )
            Divider()
            AnalyticsGlossaryRow(
                title: AppStrings.wallTime,
                bodyText: AppStrings.localized("analytics.glossary.wall")
            )
            Divider()
            AnalyticsGlossaryRow(
                title: AppStrings.localized("analytics.metric.overlap"),
                bodyText: AppStrings.localized("analytics.glossary.overlap")
            )
        }
    }
}

private struct AnalyticsGlossaryRow: View {
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

struct AnalyticsInsightList: View {
    let insights: [AnalyticsInsight]

    var body: some View {
        Group {
            if insights.isEmpty {
                EmptyStateRow(
                    title: AppStrings.localized("analytics.insight.noData.title"),
                    icon: "lightbulb"
                )
            } else {
                VStack(spacing: 0) {
                    // `EnumeratedSequence` only gains the collection conformance that
                    // `ForEach` needs on the newest OS releases. Materialize this small
                    // presentation list so the app keeps its existing deployment targets.
                    ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                        AnalyticsInsightRow(insight: insight)
                        if index < insights.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("analytics.decisionSummary")
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
                    .fixedSize(horizontal: false, vertical: true)
                Text(insight.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
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
