import SwiftUI

struct ActiveTimersSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.activeTimers)

            VStack(spacing: 0) {
                if store.activeSegments.isEmpty {
                    EmptyStateRow(title: AppStrings.noActiveTimers, icon: "pause.circle")
                } else {
                    ForEach(store.activeSegments, id: \.id) { segment in
                        ActiveTimerRow(store: store, segment: segment)
                        if segment.id != store.activeSegments.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .appCard(padding: 0)
        }
        .accessibilityIdentifier("home.activeTimers")
    }
}

struct PausedSessionsSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        Group {
            if !store.pausedSessions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: AppStrings.pausedSessions)

                    VStack(spacing: 0) {
                        ForEach(store.pausedSessions, id: \.id) { session in
                            PausedSessionRow(store: store, session: session)
                            if session.id != store.pausedSessions.last?.id {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                    .appCard(padding: 0)
                }
            }
        }
        .accessibilityIdentifier("home.pausedSessions")
    }
}

struct PausedSessionRow: View {
    @ObservedObject var store: TimeTrackerStore
    let session: TimeSession

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.orange)
                .frame(width: 10, height: 10)

            TaskIcon(task: store.task(for: session.taskID))

            VStack(alignment: .leading, spacing: 3) {
                Text(store.task(for: session.taskID)?.title ?? AppStrings.localized("task.deleted"))
                    .font(.headline)
                Text(AppStrings.paused)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.resume(session: session)
            } label: {
                Image(systemName: "play.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .tint(.blue)

            Button(role: .destructive) {
                store.stop(session: session)
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(session.taskID, revealInToday: false)
        }
        .padding(14)
    }
}

struct ActiveTimerRow: View {
    @ObservedObject var store: TimeTrackerStore
    let segment: TimeSegment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactPhone: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isCompactPhone {
                compactContent
            } else {
                ViewThatFits(in: .horizontal) {
                    regularContent
                    compactContent
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(segment.taskID, revealInToday: false)
        }
        .padding(isCompactPhone ? 10 : 14)
    }

    private var regularContent: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                .frame(width: 10, height: 10)

            TaskIcon(task: store.task(for: segment.taskID))

            VStack(alignment: .leading, spacing: 3) {
                Text(store.displayTitle(for: segment))
                    .font(.headline)
                    .lineLimit(1)
                Text(displayPathText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .frame(minWidth: 86, alignment: .trailing)

            pauseButton(size: 32)
            stopButton(size: 32)
        }
    }

    private var compactContent: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                TaskIcon(task: store.task(for: segment.taskID), size: 34)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(store.displayTitle(for: segment))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(displayPathText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            HStack(spacing: 10) {
                DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, alignment: .leading)

                pauseButton(size: 30)
                stopButton(size: 30)
            }
        }
    }

    private var displayPathText: String {
        let path = store.displayPath(for: segment)
        return path.isEmpty ? AppStrings.rootTask : path
    }

    private func pauseButton(size: CGFloat) -> some View {
        Button {
            store.pause(segment: segment)
        } label: {
            Image(systemName: "pause.fill")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .tint(.blue)
    }

    private func stopButton(size: CGFloat) -> some View {
        Button(role: .destructive) {
            store.stop(segment: segment)
        } label: {
            Image(systemName: "stop.fill")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
    }
}

struct TimelineSection: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: AppStrings.todayTimeline)

            VStack(spacing: 0) {
                if store.timelineSegments.isEmpty {
                    EmptyStateRow(title: AppStrings.noTodaySegments, icon: "clock")
                } else {
                    ForEach(store.timelineSegments, id: \.id) { segment in
                        TimelineRow(store: store, segment: segment)
                        if segment.id != store.timelineSegments.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .appCard(padding: 0)
        }
        .accessibilityIdentifier("home.timeline")
    }
}

struct TimelineRow: View {
    @ObservedObject var store: TimeTrackerStore
    let segment: TimeSegment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompactPhone: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var tag: String {
        switch segment.source {
        case .pomodoro: return AppStrings.pomodoro
        case .manual: return AppStrings.localized("source.manual")
        default: return AppStrings.localized("source.timer")
        }
    }

    var body: some View {
        Group {
            if isCompactPhone {
                compactContent
            } else {
                ViewThatFits(in: .horizontal) {
                    regularContent
                    compactContent
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectTask(segment.taskID, revealInToday: false)
        }
        .contextMenu {
            Button {
                store.presentEditSegment(segment)
            } label: {
                Label(AppStrings.localized("timeline.editSegment"), systemImage: "pencil")
            }

            Button {
                store.presentManualTime(taskID: segment.taskID)
            } label: {
                Label(AppStrings.localized("timeline.addSimilarTime"), systemImage: "calendar.badge.plus")
            }

            Divider()

            Button(role: .destructive) {
                store.deleteSegment(segment.id)
            } label: {
                Label(AppStrings.localized("timeline.deleteSegment"), systemImage: "trash")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompactPhone ? 11 : 10)
    }

    private var regularContent: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                .frame(width: 9, height: 9)

            Text(timeRangeText)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: isCompactPhone ? 82 : 120, alignment: .leading)

            Text(store.displayTitle(for: segment))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            tagBadge
                .frame(width: 96, alignment: .center)

            durationText
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                    .frame(width: 8, height: 8)
                Text(timeRangeText)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                durationText
            }

            HStack(alignment: .center, spacing: 10) {
                Text(store.displayTitle(for: segment))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                tagBadge
            }
        }
    }

    private var tagBadge: some View {
        Text(tag)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tagColor)
            .background(tagColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .lineLimit(1)
    }

    private var durationText: some View {
        Group {
            if segment.endedAt == nil {
                Text(.app("common.now"))
                    .foregroundStyle(.blue)
            } else {
                Text(DurationFormatter.compact(Int((segment.endedAt ?? Date()).timeIntervalSince(segment.startedAt))))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.82)
    }

    private var tagColor: Color {
        switch segment.source {
        case .pomodoro: return .blue
        case .manual: return .orange
        default: return .secondary
        }
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: segment.startedAt)
        let end = segment.endedAt.map { formatter.string(from: $0) } ?? AppStrings.localized("common.now")
        return "\(start) - \(end)"
    }
}
