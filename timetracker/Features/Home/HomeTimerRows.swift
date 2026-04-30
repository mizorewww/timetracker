import SwiftUI

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
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
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
