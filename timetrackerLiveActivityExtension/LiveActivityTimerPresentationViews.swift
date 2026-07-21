import Foundation
import SwiftUI

struct TimerText: View {
    enum Style {
        case lockScreen
        case expanded
    }

    let startedAt: Date
    let isStale: Bool
    let style: Style

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            stopwatchText
                .font(
                    style == .lockScreen
                        ? .title3.monospacedDigit().weight(.semibold)
                        : .headline.monospacedDigit().weight(.semibold)
                )
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if isStale {
                Image(systemName: "exclamationmark.clock.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .frame(
            minWidth: style == .lockScreen ? 78 : 64,
            idealWidth: style == .lockScreen ? 88 : 72,
            maxWidth: style == .lockScreen ? 104 : 84,
            minHeight: 44,
            alignment: .trailing
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: isStale ? "live.timer.stale" : "live.timer.elapsed"))
        .accessibilityValue(stopwatchText)
        .accessibilityHint(
            isStale ? String(localized: "live.timer.staleHint") : ""
        )
    }

    private var stopwatchText: Text {
        Text(
            .currentDate,
            format: .stopwatch(
                startingAt: startedAt,
                showsHours: true,
                maxFieldCount: 3,
                maxPrecision: .seconds(1)
            )
        )
    }
}

struct CompactTimerText: View {
    let startedAt: Date
    let isStale: Bool

    var body: some View {
        stopwatchText
            .accessibilityValue(stopwatchText)
            .accessibilityHint(
                isStale ? String(localized: "live.timer.staleHint") : ""
            )
    }

    private var stopwatchText: Text {
        Text(
            .currentDate,
            format: .stopwatch(
                startingAt: startedAt,
                showsHours: true,
                maxFieldCount: 3,
                maxPrecision: .seconds(1)
            )
        )
    }
}
