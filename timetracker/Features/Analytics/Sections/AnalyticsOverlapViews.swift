import SwiftUI

struct AnalyticsOverlapContent: View {
    private let presentation: AnalyticsOverlapPresentation

    init(overlaps: [OverlapAnalyticsPoint]) {
        presentation = AnalyticsOverlapPresentation(overlaps: overlaps)
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentation.visibleWindows.isEmpty {
                EmptyStateRow(
                    title: AppStrings.localized("analytics.empty.overlap"),
                    icon: "rectangle.2.swap"
                )
            } else {
                ForEach(presentation.visibleWindows) { overlap in
                    AnalyticsOverlapRow(overlap: overlap)
                    if overlap.id != presentation.visibleWindows.last?.id {
                        Divider()
                    }
                }

                if presentation.hiddenWindowCount > 0 {
                    Divider()
                    AnalyticsOverlapHiddenSummary(
                        windowCount: presentation.hiddenWindowCount,
                        excessSeconds: presentation.hiddenExcessSeconds
                    )
                }
            }
        }
    }
}

struct AnalyticsOverlapPresentation {
    let visibleWindows: [OverlapAnalyticsPoint]
    let hiddenWindowCount: Int
    let hiddenExcessSeconds: Int

    init(overlaps: [OverlapAnalyticsPoint], maximumVisibleWindows: Int = 6) {
        let visibleCount = min(max(0, maximumVisibleWindows), overlaps.count)
        visibleWindows = Array(overlaps.prefix(visibleCount))
        hiddenWindowCount = overlaps.count - visibleCount
        hiddenExcessSeconds = overlaps.dropFirst(visibleCount).reduce(0) {
            $0 + $1.excessDurationSeconds
        }
    }
}

private struct AnalyticsOverlapHiddenSummary: View {
    @Environment(\.locale) private var locale

    let windowCount: Int
    let excessSeconds: Int

    var body: some View {
        Label {
            Text(summaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryText)
        .accessibilityIdentifier("analytics.overlap.hiddenSummary")
    }

    private var summaryText: String {
        String.localizedStringWithFormat(
            AppStrings.localized(
                windowCount == 1
                    ? "analytics.overlap.hiddenSummaryOneWindowFormat"
                    : "analytics.overlap.hiddenSummaryFormat"
            ),
            windowCount,
            AnalyticsOverlapFormatting.duration(excessSeconds, locale: locale)
        )
    }
}

enum AnalyticsOverlapFormatting {
    static func duration(_ seconds: Int, locale: Locale) -> String {
        if seconds > 0, seconds < 60 {
            return DurationFormatter.spoken(seconds, locale: locale)
        }
        return DurationFormatter.compact(seconds, locale: locale)
    }
}
