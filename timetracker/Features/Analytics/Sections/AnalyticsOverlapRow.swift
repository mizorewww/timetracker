import SwiftUI

struct AnalyticsOverlapRow: View {
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
                    .font(primaryFont.weight(.medium))
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
                .font(primaryFont.monospacedDigit())
        }
    }

    private var primaryFont: Font {
        #if os(macOS)
        .body
        #else
        .subheadline
        #endif
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
