import Foundation
import SwiftUI

enum WatchRowCommandState: Equatable {
    case idle
    case pending
    case failed
}

struct WatchTaskShortcutRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let task: WatchRecentTaskSnapshot
    let commandState: WatchRowCommandState
    let action: () -> Void

    private var tint: Color {
        Color(hex: task.colorHex) ?? .blue
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                WatchIconTile(systemImage: task.iconName ?? "play.fill", tint: tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .multilineTextAlignment(.leading)
                        .privacySensitive()
                        .redacted(reason: isLuminanceReduced ? .placeholder : [])

                    if !dynamicTypeSize.isAccessibilitySize, !task.path.isEmpty {
                        Text(task.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()
                            .redacted(reason: isLuminanceReduced ? .placeholder : [])
                    }
                }

                Spacer(minLength: 2)

                Image(systemName: commandState.taskSystemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(commandState.tint(default: tint))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(commandState == .pending)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(commandState.taskHintKey))
    }

    private var accessibilityLabel: String {
        commandState.accessibilityLabel(
            task.path.isEmpty ? task.title : "\(task.title), \(task.path)"
        )
    }
}

struct WatchActiveTimerRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let timer: WatchActiveTimerSnapshot
    let snapshotFreshness: WatchSnapshotFreshness
    let generatedAt: Date
    let commandState: WatchRowCommandState
    let action: () -> Void

    private var tint: Color {
        Color(hex: timer.colorHex) ?? .blue
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    WatchIconTile(systemImage: timer.iconName ?? "timer", tint: tint)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(timer.title)
                            .font(.headline)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                            .multilineTextAlignment(.leading)
                            .privacySensitive()
                            .redacted(reason: isLuminanceReduced ? .placeholder : [])

                        if !dynamicTypeSize.isAccessibilitySize, !timer.path.isEmpty {
                            Text(timer.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .privacySensitive()
                                .redacted(reason: isLuminanceReduced ? .placeholder : [])
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: commandState.timerSystemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(commandState.tint(default: tint))
                        .accessibilityHidden(true)
                }

                ViewThatFits(in: .horizontal) {
                    elapsedText
                        .font(.title2.monospacedDigit())
                        .lineLimit(1)
                    elapsedText
                        .font(.headline.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(commandState == .pending)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(elapsedAccessibilityValue)
        .accessibilityHint(Text(commandState.timerHintKey))
    }

    @ViewBuilder
    private var elapsedText: some View {
        switch elapsedPresentation {
        case let .live(startedAt):
            Text(startedAt, style: .timer)
        case let .frozen(seconds):
            Text(WatchElapsedFormatter.clock(seconds))
        }
    }

    private var elapsedAccessibilityValue: Text {
        switch elapsedPresentation {
        case let .live(startedAt):
            Text(startedAt, style: .timer)
        case let .frozen(seconds):
            Text(WatchElapsedFormatter.clock(seconds))
        }
    }

    private var elapsedPresentation: WatchTimerElapsedPresentation {
        timer.elapsedPresentation(
            for: snapshotFreshness,
            generatedAt: generatedAt
        )
    }

    private var accessibilityLabel: String {
        commandState.accessibilityLabel(
            timer.path.isEmpty ? timer.title : "\(timer.title), \(timer.path)"
        )
    }
}

private enum WatchElapsedFormatter {
    static func clock(_ seconds: Int) -> String {
        Duration.seconds(max(0, seconds)).formatted(
            .time(pattern: .hourMinuteSecond).locale(.autoupdatingCurrent)
        )
    }
}

private extension WatchRowCommandState {
    func accessibilityLabel(_ baseLabel: String) -> String {
        guard let accessibilityStatus else { return baseLabel }
        return "\(baseLabel), \(String(localized: accessibilityStatus))"
    }

    var accessibilityStatus: LocalizedStringResource? {
        switch self {
        case .idle: nil
        case .pending: "watch.commandState.pending"
        case .failed: "watch.commandState.failed"
        }
    }

    var taskSystemImage: String {
        switch self {
        case .idle: "play.fill"
        case .pending: "hourglass"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var timerSystemImage: String {
        switch self {
        case .idle: "stop.fill"
        case .pending: "hourglass"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var taskHintKey: LocalizedStringKey {
        switch self {
        case .idle: "watch.tasks.startHint"
        case .pending: "watch.tasks.pendingHint"
        case .failed: "watch.tasks.failedHint"
        }
    }

    var timerHintKey: LocalizedStringKey {
        switch self {
        case .idle: "watch.tasks.stopHint"
        case .pending: "watch.tasks.pendingHint"
        case .failed: "watch.tasks.failedHint"
        }
    }

    func tint(`default`: Color) -> Color {
        switch self {
        case .idle: `default`
        case .pending: .secondary
        case .failed: .orange
        }
    }
}
