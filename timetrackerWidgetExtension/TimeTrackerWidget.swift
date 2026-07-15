import Foundation
import SwiftUI
import WidgetKit

struct ActiveTimerEntry: TimelineEntry {
    let date: Date
    let state: WidgetEntryState
}

enum WidgetEntryState: Equatable {
    case placeholder(WidgetSnapshot)
    case snapshot(WidgetSnapshot)
    case unavailable(WidgetDataIssue)
}

enum WidgetDataIssue: Equatable {
    case sharedContainerUnavailable
    case missing
    case corrupted
}

struct ActiveTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveTimerEntry {
        ActiveTimerEntry(date: Date(), state: .placeholder(Self.previewSnapshot()))
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveTimerEntry) -> Void) {
        if context.isPreview {
            completion(ActiveTimerEntry(date: Date(), state: .snapshot(Self.previewSnapshot())))
        } else {
            completion(entry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveTimerEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)

        switch current.state {
        case let .snapshot(snapshot) where snapshot.freshness(at: now) == .current:
            let staleDate = snapshot.generatedAt.addingTimeInterval(WidgetSnapshot.staleAfter)
            completion(Timeline(entries: [current], policy: .after(max(staleDate, now.addingTimeInterval(60)))))
        default:
            // The host app reloads this timeline whenever it writes a new snapshot.
            completion(Timeline(entries: [current], policy: .never))
        }
    }

    private func entry(at date: Date) -> ActiveTimerEntry {
        let state: WidgetEntryState
        switch SharedWidgetSnapshotStore().loadResult() {
        case let .snapshot(snapshot):
            state = .snapshot(snapshot)
        case .sharedContainerUnavailable:
            state = .unavailable(.sharedContainerUnavailable)
        case .missing:
            state = .unavailable(.missing)
        case .corrupted:
            state = .unavailable(.corrupted)
        }
        return ActiveTimerEntry(date: date, state: state)
    }

    private static func previewSnapshot(now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now,
            todayGrossSeconds: 3_900,
            todayWallSeconds: 5_100,
            activeTimers: [
                WidgetTimerSnapshot(
                    id: UUID(uuidString: "E13DC2F2-4F2B-46A0-8FF0-7BA77252B86B")!,
                    taskID: UUID(uuidString: "510DF5D1-2F55-41E6-A0D5-6E5B6BD13A5A")!,
                    title: localized("widget.preview.task"),
                    path: localized("widget.preview.path"),
                    startedAt: now.addingTimeInterval(-15 * 60),
                    colorHex: "3478F6",
                    iconName: "hammer.fill"
                )
            ],
            recentTasks: []
        )
    }
}

struct TimeTrackerActiveTimerWidget: Widget {
    let kind = SharedWidgetSnapshotStore.widgetKind

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
