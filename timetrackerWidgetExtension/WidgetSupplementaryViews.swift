import SwiftUI

struct MediumWidgetContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            SmallWidgetContent(snapshot: snapshot, now: now)
        } else {
            regularContent
        }
    }

    private var regularContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
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
                        Text(localized("widget.empty.message"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        SnapshotFreshnessLabel(
                            freshness: snapshot.freshness(at: now),
                            generatedAt: snapshot.generatedAt
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text(localized("widget.quickStart.title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if snapshot.recentTasks.isEmpty {
                    Link(destination: WidgetDeepLinks.today) {
                        Label(localized("widget.action.open"), systemImage: "arrow.up.forward.app")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                } else {
                    ForEach(snapshot.recentTasks.prefix(2)) { task in
                        Link(destination: WidgetDeepLinks.startTimer(taskID: task.taskID)) {
                            HStack(spacing: 6) {
                                TaskGlyph(iconName: task.iconName, colorHex: task.colorHex)
                                Text(task.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .privacySensitive()
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel(
                            Text("\(localized("widget.action.start")), \(task.title)")
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SnapshotFreshnessLabel: View {
    let freshness: WidgetSnapshotFreshness
    let generatedAt: Date

    var body: some View {
        switch freshness {
        case .current:
            EmptyView()
        case .stale:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.clock")
                    .accessibilityHidden(true)
                Text(generatedAt, style: .relative)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(localized("widget.stale.label")))
            .accessibilityValue(Text(generatedAt, style: .relative))
        case .clockAdjusted:
            Label(localized("widget.clockAdjusted.label"), systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct WidgetIssueContent: View {
    let issue: WidgetDataIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: issue == .corrupted ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(localized(titleKey))
                .font(.headline)
                .lineLimit(2)
            Text(localized(messageKey))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Label(localized("widget.action.open"), systemImage: "arrow.up.forward.app")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var titleKey: String {
        issue == .corrupted ? "widget.corrupted.title" : "widget.unavailable.title"
    }

    private var messageKey: String {
        issue == .corrupted ? "widget.corrupted.message" : "widget.unavailable.message"
    }
}

struct TaskGlyph: View {
    let iconName: String?
    let colorHex: String?

    var body: some View {
        Image(systemName: iconName?.isEmpty == false ? iconName ?? "timer" : "timer")
            .font(.headline)
            .foregroundStyle(color)
            .padding(6)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }

    private var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}
