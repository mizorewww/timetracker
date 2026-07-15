import Foundation
import SwiftUI
import WidgetKit

struct ActiveTimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActiveTimerEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(widgetURL)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case let .placeholder(snapshot):
            widgetContent(snapshot: snapshot)
                .redacted(reason: .placeholder)
        case let .snapshot(snapshot):
            widgetContent(snapshot: snapshot)
        case let .unavailable(issue):
            WidgetIssueContent(issue: issue)
        }
    }

    @ViewBuilder
    private func widgetContent(snapshot: WidgetSnapshot) -> some View {
        switch family {
        case .systemMedium:
            MediumWidgetContent(snapshot: snapshot, now: entry.date)
        default:
            SmallWidgetContent(snapshot: snapshot, now: entry.date)
        }
    }

    private var widgetURL: URL {
        guard case let .snapshot(snapshot) = entry.state,
              snapshot.activeTimers.isEmpty,
              let task = snapshot.recentTasks.first else {
            return WidgetDeepLinks.today
        }
        return WidgetDeepLinks.startTimer(taskID: task.taskID)
    }
}

struct SmallWidgetContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        if let timer = snapshot.activeTimers.first {
            ActiveTimerContent(
                timer: timer,
                count: snapshot.activeTimers.count,
                freshness: snapshot.freshness(at: now),
                generatedAt: snapshot.generatedAt
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text(localized("widget.empty.title"))
                    .font(.headline)
                    .lineLimit(2)

                if !dynamicTypeSize.isAccessibilitySize {
                    Text(localized("widget.empty.message"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let task = snapshot.recentTasks.first {
                    Label(task.title, systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .privacySensitive()
                } else {
                    Label(localized("widget.action.open"), systemImage: "arrow.up.forward.app")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }

                SnapshotFreshnessLabel(
                    freshness: snapshot.freshness(at: now),
                    generatedAt: snapshot.generatedAt
                )
            }
        }
    }
}

struct ActiveTimerContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let timer: WidgetTimerSnapshot
    let count: Int
    let freshness: WidgetSnapshotFreshness
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TaskGlyph(iconName: timer.iconName, colorHex: timer.colorHex)
                Text(timer.title)
                    .font(.headline)
                    .lineLimit(2)
                    .privacySensitive()
                Spacer(minLength: 0)
            }

            Text(timer.startedAt, style: .timer)
                .font(.system(.title2, design: .rounded).monospacedDigit())
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityLabel(Text(localized("widget.elapsed.label")))
                .accessibilityValue(Text(timer.startedAt, style: .timer))

            if !dynamicTypeSize.isAccessibilitySize, !timer.path.isEmpty {
                Text(timer.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }

            if count > 1 {
                Text(String.localizedStringWithFormat(localized("widget.active.more"), count - 1))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            SnapshotFreshnessLabel(freshness: freshness, generatedAt: generatedAt)
        }
    }
}
