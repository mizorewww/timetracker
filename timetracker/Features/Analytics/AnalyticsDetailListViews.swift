import SwiftUI

struct AnalyticsGlossaryList: View {
    var body: some View {
        VStack(spacing: 0) {
            Text(.app("analytics.glossary.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .accessibilityIdentifier("analytics.definition.introduction")
            Divider()
            AnalyticsGlossaryRow(
                title: AppStrings.grossTime,
                bodyText: AppStrings.localized("analytics.glossary.gross"),
                calculationText: AppStrings.localized(
                    "analytics.glossary.gross.calculation"
                ),
                identifier: "analytics.definition.gross"
            )
            Divider()
            AnalyticsGlossaryRow(
                title: AppStrings.wallTime,
                bodyText: AppStrings.localized("analytics.glossary.wall"),
                calculationText: AppStrings.localized(
                    "analytics.glossary.wall.calculation"
                ),
                identifier: "analytics.definition.wall"
            )
            Divider()
            AnalyticsGlossaryRow(
                title: AppStrings.localized("analytics.metric.overlap"),
                bodyText: AppStrings.localized("analytics.glossary.overlap"),
                calculationText: AppStrings.localized(
                    "analytics.glossary.overlap.calculation"
                ),
                identifier: "analytics.definition.overlap"
            )
            Divider()
            AnalyticsGlossaryExample()
        }
    }
}

private struct AnalyticsGlossaryRow: View {
    let title: String
    let bodyText: String
    let calculationText: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(bodyText)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Text(calculationText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct AnalyticsGlossaryExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(.app("analytics.glossary.example.title"))
                .font(.subheadline.weight(.semibold))
            Text(.app("analytics.glossary.example.body"))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.definition.example")
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
            "checkmark.seal"
        case .neutral:
            "target"
        case .warning:
            "exclamationmark.triangle"
        case .critical:
            "exclamationmark.octagon"
        }
    }

    private var tint: Color {
        switch insight.severity {
        case .positive:
            .green
        case .neutral:
            .blue
        case .warning:
            .orange
        case .critical:
            .red
        }
    }
}
