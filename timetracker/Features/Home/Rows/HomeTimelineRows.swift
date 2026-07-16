import SwiftUI

struct TimelineRow: View {
    let store: TimeTrackerStore
    let segment: TimeSegment
    var openTaskDetail: ((UUID) -> Void)? = nil
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isDeleteConfirmationPresented = false
    @State private var deleteBaseline: SegmentEditorDraftBaseline?

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
            taskButton(at: Date())

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
                store.deleteSegment(
                    segment.id,
                    expectedBaseline: deleteBaseline
                )
                deleteBaseline = nil
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("segment.delete.confirm.message"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isCompactPhone ? 11 : 10)
    }

    private func taskButton(at now: Date) -> some View {
        let display = TrackedTimeDisplaySnapshot(
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            now: now
        )

        return Button(action: openTask) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    accessibilityContent(display: display)
                } else if isCompactPhone {
                    compactContent(display: display)
                } else {
                    ViewThatFits(in: .horizontal) {
                        regularContent(display: display)
                        compactContent(display: display)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppStrings.localized("tasks.openDetail"))
    }

    private func accessibilityContent(display: TrackedTimeDisplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.displayTitle(for: segment))
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(timeRangeText(display: display))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    tagBadge
                    Spacer(minLength: 8)
                    durationText
                }
                VStack(alignment: .leading, spacing: 6) {
                    tagBadge
                    durationText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var segmentActions: some View {
        Button {
            presentationRouter.presentEditSegment(segment, using: store)
        } label: {
            Label(AppStrings.localized("timeline.editSegment"), systemImage: "pencil")
        }

        Button {
            presentationRouter.presentManualTime(taskID: segment.taskID, using: store)
        } label: {
            Label(AppStrings.localized("timeline.addSimilarTime"), systemImage: "calendar.badge.plus")
        }

        Divider()

        Button(role: .destructive) {
            guard let draft = store.segmentEditorDraft(for: segment) else {
                store.errorMessage = SegmentMutationError.inconsistentSession.localizedDescription
                return
            }
            deleteBaseline = draft.baseline
            isDeleteConfirmationPresented = true
        } label: {
            Label(AppStrings.localized("timeline.deleteSegment"), systemImage: "trash")
        }
    }

    private func regularContent(display: TrackedTimeDisplaySnapshot) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                .frame(width: 9, height: 9)

            Text(timeRangeText(display: display))
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

    private func compactContent(display: TrackedTimeDisplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Color(hex: store.task(for: segment.taskID)?.colorHex) ?? .blue)
                    .frame(width: 8, height: 8)
                Text(timeRangeText(display: display))
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
        DurationLabel(startedAt: segment.startedAt, endedAt: segment.endedAt)
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(segment.endedAt == nil ? Color.blue : Color.secondary)
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

    private func timeRangeText(display: TrackedTimeDisplaySnapshot) -> String {
        let start = TimeDisplayFormatter.hourMinute(display.start)
        let end = display.usesCurrentEndLabel
            ? AppStrings.localized("common.now")
            : TimeDisplayFormatter.hourMinute(display.end)
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
