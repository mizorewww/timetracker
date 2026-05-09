import Foundation
import SwiftUI
import WidgetKit

struct ActiveTimerEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct ActiveTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveTimerEntry {
        ActiveTimerEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveTimerEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveTimerEntry>) -> Void) {
        let current = entry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 1, to: current.date) ?? current.date.addingTimeInterval(60)
        completion(Timeline(entries: [current], policy: .after(nextRefresh)))
    }

    private func entry() -> ActiveTimerEntry {
        ActiveTimerEntry(
            date: Date(),
            snapshot: SharedWidgetSnapshotStore().load() ?? .empty
        )
    }
}

struct ActiveTimerWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActiveTimerEntry

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            .widgetURL(WidgetDeepLinks.today)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            MediumWidgetContent(snapshot: entry.snapshot)
        default:
            if let timer = entry.snapshot.activeTimers.first {
                ActiveTimerContent(timer: timer, count: entry.snapshot.activeTimers.count)
            } else {
                EmptyTimerContent(recentTasks: entry.snapshot.recentTasks)
            }
        }
    }
}

private struct ActiveTimerContent: View {
    let timer: WidgetTimerSnapshot
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TaskGlyph(iconName: timer.iconName, colorHex: timer.colorHex)
                Text(timer.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            Text(timer.startedAt, style: .timer)
                .font(.system(.title2, design: .rounded).monospacedDigit())
                .fontWeight(.semibold)

            if timer.path.isEmpty == false {
                Text(timer.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if count > 1 {
                Text(String(format: localized("widget.active.more"), count - 1))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct EmptyTimerContent: View {
    let recentTasks: [WidgetRecentTaskSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(.blue)
            Text(localized("widget.empty.title"))
                .font(.headline)
            Text(localized("widget.empty.message"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Link(destination: WidgetDeepLinks.startTimer) {
                Label(localized("widget.action.start"), systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
            }

            if let task = recentTasks.first {
                Link(destination: WidgetDeepLinks.startTimer(taskID: task.taskID)) {
                    Label(task.title, systemImage: "clock.arrow.circlepath")
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct MediumWidgetContent: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let timer = snapshot.activeTimers.first {
                ActiveTimerContent(timer: timer, count: snapshot.activeTimers.count)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                EmptyTimerContent(recentTasks: [])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("widget.quickStart.title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if snapshot.recentTasks.isEmpty {
                    Link(destination: WidgetDeepLinks.startTimer) {
                        Label(localized("widget.action.start"), systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                } else {
                    ForEach(snapshot.recentTasks.prefix(3)) { task in
                        Link(destination: WidgetDeepLinks.startTimer(taskID: task.taskID)) {
                            HStack(spacing: 6) {
                                TaskGlyph(iconName: task.iconName, colorHex: task.colorHex)
                                    .frame(width: 24, height: 24)
                                Text(task.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TaskGlyph: View {
    let iconName: String?
    let colorHex: String?

    var body: some View {
        Image(systemName: iconName?.isEmpty == false ? iconName ?? "timer" : "timer")
            .font(.headline)
            .foregroundStyle(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var color: Color {
        Color(hex: colorHex) ?? .blue
    }
}

struct TimeTrackerActiveTimerWidget: Widget {
    let kind = "TimeTrackerActiveTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveTimerProvider()) { entry in
            ActiveTimerWidgetView(entry: entry)
        }
        .configurationDisplayName(localized("widget.active.displayName"))
        .description(localized("widget.active.description"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TimeTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimeTrackerActiveTimerWidget()
    }
}

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private enum WidgetDeepLinks {
    static let today = URL(string: "timetracker://open/today")!
    static let startTimer = URL(string: "timetracker://timer/start")!

    static func startTimer(taskID: UUID) -> URL {
        URL(string: "timetracker://timer/start?taskID=\(taskID.uuidString)")!
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
