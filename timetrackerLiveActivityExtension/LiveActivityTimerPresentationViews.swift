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
            elapsedText
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
        .accessibilityValue(elapsedAccessibilityValue)
        .accessibilityHint(
            isStale ? String(localized: "live.timer.staleHint") : ""
        )
    }

    @ViewBuilder
    private var elapsedText: some View {
        switch elapsedPresentation {
        case let .live(startedAt):
            liveElapsedText(startedAt: startedAt)
        case let .frozen(seconds):
            Text(LiveActivityElapsedFormatter.clock(seconds))
        }
    }

    private func liveElapsedText(startedAt: Date) -> Text {
        Text(
            timerInterval: startedAt...LiveActivityTimingPolicy.staleDate(for: startedAt),
            countsDown: false,
            showsHours: true
        )
    }

    private var elapsedAccessibilityValue: Text {
        switch elapsedPresentation {
        case let .live(startedAt):
            liveElapsedText(startedAt: startedAt)
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
            liveElapsedText(startedAt: startedAt)
        case let .frozen(seconds):
            Text(LiveActivityElapsedFormatter.clock(seconds))
        }
    }

    private func liveElapsedText(startedAt: Date) -> Text {
        Text(
            timerInterval: startedAt...LiveActivityTimingPolicy.staleDate(for: startedAt),
            countsDown: false,
            showsHours: true
        )
    }

    private var elapsedAccessibilityValue: Text {
        switch elapsedPresentation {
        case let .live(startedAt):
            liveElapsedText(startedAt: startedAt)
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
