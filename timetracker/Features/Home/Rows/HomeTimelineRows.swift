import SwiftUI

struct TimelineRow: View {
    let store: TimeTrackerStore
    let segment: TimeSegment
    var openTaskDetail: ((UUID) -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isDeleteConfirmationPresented = false

    private var isCompactPhone: Bool {
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
    }

    private var tag: String {
        switch segment.source {
        case .pomodoro: return AppStrings.pomodoro
        case .manual: return AppStrings.localized("source.manual")
        default: return AppStrings.localized("source.timer")
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: openTask) {
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
            }
            .buttonStyle(.plain)
            .accessibilityHint(AppStrings.localized("tasks.openDetail"))

            Menu {
                segmentActions
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(AppStrings.localized("common.more"))
        }
        .contextMenu { segmentActions }

        .confirmationDialog(
            AppStrings.localized("segment.delete.confirm.title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(AppStrings.localized("timeline.deleteSegment"), role: .destructive) {
                store.deleteSegment(segment.id)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("segment.delete.confirm.message"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompactPhone ? 11 : 10)
    }

    @ViewBuilder
    private var segmentActions: some View {
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
            isDeleteConfirmationPresented = true
        } label: {
            Label(AppStrings.localized("timeline.deleteSegment"), systemImage: "trash")
        }
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
        let start = TimeDisplayFormatter.hourMinute(segment.startedAt)
        let end = segment.endedAt.map { TimeDisplayFormatter.hourMinute($0) } ?? AppStrings.localized("common.now")
        return "\(start) - \(end)"
    }

    private func openTask() {
        if let openTaskDetail {
            openTaskDetail(segment.taskID)
        } else {
            store.openTaskDetail(segment.taskID)
        }
    }
}
