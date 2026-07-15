import SwiftUI

struct ActiveTimerRow: View {
    let store: TimeTrackerStore
    let segment: TimeSegment
    var openTaskDetail: ((UUID) -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isCompactPhone: Bool {
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
    }

    var body: some View {
        Group {
            if isCompactPhone && dynamicTypeSize.isAccessibilitySize {
                accessibilityContent
            } else if isCompactPhone {
                compactContent
            } else {
                ViewThatFits(in: .horizontal) {
                    regularContent
                    compactContent
                }
            }
        }
        .padding(isCompactPhone ? 10 : 14)
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: openTask) {
                    HStack(alignment: .top, spacing: 12) {
                        TaskIcon(task: store.task(for: segment.taskID), size: 34)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.displayTitle(for: segment))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(displayPathText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(AppStrings.localized("tasks.openDetail"))

                stopButton(size: 30)
            }

            DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .padding(.leading, 46)
        }
    }

    private var regularContent: some View {
        HStack(spacing: 12) {
            Button(action: openTask) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                        .frame(width: 10, height: 10)

                    TaskIcon(task: store.task(for: segment.taskID))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.displayTitle(for: segment))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(displayPathText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 10)

                    DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
                        .font(.title.weight(.medium).monospacedDigit())
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.75)
                        .frame(minWidth: 86, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(AppStrings.localized("tasks.openDetail"))

            stopButton(size: 32)
        }
    }

    private var compactContent: some View {
        HStack(spacing: 10) {
            Button(action: openTask) {
                HStack(alignment: .center, spacing: 12) {
                    TaskIcon(task: store.task(for: segment.taskID), size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.displayTitle(for: segment))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(displayPathText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(AppStrings.localized("tasks.openDetail"))

            Spacer(minLength: 0)
            stopButton(size: 30)
        }
    }

    private var displayPathText: String {
        let path = store.displayPath(for: segment)
        return path.isEmpty ? AppStrings.rootTask : path
    }

    private func stopButton(size: CGFloat) -> some View {
        Button(role: .destructive) {
            store.stop(segment: segment)
        } label: {
            Image(systemName: "stop.fill")
                .frame(width: size, height: size)
        }
        .buttonStyle(.bordered)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(AppStrings.localized("timer.action.stop"))
    }

    private func openTask() {
        if let openTaskDetail {
            openTaskDetail(segment.taskID)
        } else {
            store.openTaskDetail(segment.taskID)
        }
    }
}
