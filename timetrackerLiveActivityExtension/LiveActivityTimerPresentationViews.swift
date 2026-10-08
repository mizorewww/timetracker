import Foundation
import SwiftUI

/// Shared stopwatch `Text` used by the lock-screen row, the Dynamic Island row
/// and both compact regions so they can never disagree about the elapsed value.
func liveActivityStopwatchText(startedAt: Date) -> Text {
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

struct TimerText: View {
    enum Style {
        case lockScreen
        case expanded

        var iconSize: CGFloat {
            self == .lockScreen ? 34 : 30
        }

        var showsPath: Bool {
            self == .lockScreen
        }
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
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(
            style == .lockScreen
                ? "liveActivity.lockScreen.timer"
                : "liveActivity.expanded.timer"
        )
    }

    private var stopwatchText: Text {
        liveActivityStopwatchText(startedAt: startedAt)
    }
}
