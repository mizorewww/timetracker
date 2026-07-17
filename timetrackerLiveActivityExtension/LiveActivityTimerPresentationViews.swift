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
        VStack(alignment: .trailing, spacing: 2) {
            elapsedText
                .font(
                    style == .lockScreen
                        ? .title2.monospacedDigit().weight(.semibold)
                        : .headline.monospacedDigit().weight(.semibold)
                )
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Label(
                String(localized: isStale ? "live.timer.stale" : "live.timer.elapsed"),
                systemImage: isStale ? "exclamationmark.clock" : "clock"
            )
            .labelStyle(.titleAndIcon)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.66))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: isStale ? "live.timer.stale" : "live.timer.elapsed"))
        .accessibilityValue(elapsedAccessibilityValue)
        .accessibilityHint(
            isStale ? String(localized: "live.timer.staleHint") : ""
        )
    }

    @ViewBuilder
    private var elapsedText: some View {
        switch elapsedPresentation {
        case let .live(startedAt):
            Text(startedAt, style: .timer)
        case let .frozen(seconds):
            Text(LiveActivityElapsedFormatter.clock(seconds))
        }
    }

    private var elapsedAccessibilityValue: Text {
        switch elapsedPresentation {
        case let .live(startedAt):
            Text(startedAt, style: .timer)
        case let .frozen(seconds):
            Text(LiveActivityElapsedFormatter.clock(seconds))
        }
    }

    private var elapsedPresentation: LiveActivityElapsedPresentation {
        LiveActivityTimingPolicy.elapsedPresentation(
            startedAt: startedAt,
            isStale: isStale
        )
    }
}

struct CompactTimerText: View {
    let startedAt: Date
    let isStale: Bool

    var body: some View {
        elapsedText
            .accessibilityValue(elapsedAccessibilityValue)
    }

    @ViewBuilder
    private var elapsedText: some View {
        switch elapsedPresentation {
        case let .live(startedAt):
            Text(startedAt, style: .timer)
        case let .frozen(seconds):
            Text(LiveActivityElapsedFormatter.clock(seconds))
        }
    }

    private var elapsedAccessibilityValue: Text {
        switch elapsedPresentation {
        case let .live(startedAt):
            Text(startedAt, style: .timer)
        case let .frozen(seconds):
            Text(LiveActivityElapsedFormatter.clock(seconds))
        }
    }

    private var elapsedPresentation: LiveActivityElapsedPresentation {
        LiveActivityTimingPolicy.elapsedPresentation(
            startedAt: startedAt,
            isStale: isStale
        )
    }
}
