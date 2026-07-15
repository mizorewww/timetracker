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

private struct AnalyticsOverlapRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    let overlap: OverlapAnalyticsPoint

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    identity
                    duration
                }
            } else {
                HStack(spacing: 12) {
                    identity
                    Spacer(minLength: 8)
                    duration
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(participantText)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("analytics.overlap.window")
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "rectangle.2.swap")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(participantText)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeRangeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(concurrencyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var duration: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text("analytics.overlap.excess.label")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(AnalyticsOverlapFormatting.duration(overlap.excessDurationSeconds, locale: locale))
                .font(.subheadline.monospacedDigit())
        }
    }

    private var participantText: String {
        let formatter = ListFormatter()
        formatter.locale = locale
        let names = overlap.visibleParticipants.map(\.title)
        let visibleNames = formatter.string(from: names)
            ?? names.joined(separator: ", ")

        guard overlap.hiddenParticipantCount > 0 else { return visibleNames }
        return String.localizedStringWithFormat(
            AppStrings.localized(
                overlap.hiddenParticipantCount == 1
                    ? "analytics.overlap.oneMoreParticipantFormat"
                    : "analytics.overlap.moreParticipantsFormat"
            ),
            visibleNames,
            overlap.hiddenParticipantCount
        )
    }

    private var timeRangeText: String {
        String.localizedStringWithFormat(
            AppStrings.localized("analytics.overlap.timeRangeFormat"),
            TimeDisplayFormatter.monthDayHourMinute(overlap.start, locale: locale),
            TimeDisplayFormatter.hourMinute(overlap.end, locale: locale)
        )
    }

    private var concurrencyText: String {
        String.localizedStringWithFormat(
            AppStrings.localized(
                overlap.participantCount == 1
                    ? "analytics.overlap.concurrencyOneTaskFormat"
                    : "analytics.overlap.concurrencyFormat"
            ),
            overlap.concurrentSegmentCount,
            overlap.participantCount
        )
    }

    private var excessText: String {
        String.localizedStringWithFormat(
            AppStrings.localized("analytics.overlap.excessFormat"),
            AnalyticsOverlapFormatting.duration(overlap.excessDurationSeconds, locale: locale)
        )
    }

    private var accessibilityValue: String {
        String.localizedStringWithFormat(
            AppStrings.localized("analytics.overlap.accessibility.valueFormat"),
            timeRangeText,
            concurrencyText,
            excessText
        )
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

private enum AnalyticsOverlapFormatting {
    static func duration(_ seconds: Int, locale: Locale) -> String {
        if seconds > 0, seconds < 60 {
            return DurationFormatter.spoken(seconds, locale: locale)
        }
        return DurationFormatter.compact(seconds, locale: locale)
    }
}
