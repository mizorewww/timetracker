import SwiftUI

struct TimelineRow: View {
    let store: TimeTrackerStore
    let segment: TimeSegment
    var openTaskDetail: ((UUID) -> Void)?
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pendingDeletionRequest: SegmentEditorDraftBaseline?

    private var isCompact: Bool {
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompact
    }

    private var tag: String {
        switch segment.source {
        case .pomodoro: AppStrings.pomodoro
        case .manual: AppStrings.localized("source.manual")
        default: AppStrings.localized("source.timer")
        }
    }

    private var taskVisual: TaskVisualPresentation {
        let task = store.task(for: segment.taskID)
        return TaskVisualPresentation(
            iconName: task?.iconName,
            colorHex: task?.colorHex
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            taskButton(at: Date())

            Menu {
                segmentActions
            } label: {
                TrailingMenuLabel(systemImage: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(AppStrings.localized("common.more"))
            .accessibilityIdentifier(
                "timeline.more.\(segment.source.rawValue).\(segment.id.uuidString)"
            )
        }
        .contextMenu { segmentActions }
        .confirmationDialog(
            pendingDeletionImpact.confirmationTitle,
            isPresented: deletionPresentation,
            titleVisibility: .visible
        ) {
            Button(
                pendingDeletionImpact.confirmationActionTitle,
                role: .destructive
            ) {
                guard let pendingDeletionRequest else { return }
                store.deleteSegment(
                    segment.id,
                    expectedBaseline: pendingDeletionRequest
                )
                self.pendingDeletionRequest = nil
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(pendingDeletionImpact.confirmationMessage)
        }
        .padding(.leading, 14)
        .padding(.trailing, isCompact ? 0 : 14)
        .padding(.vertical, isCompact ? 11 : 10)
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
                } else if isCompact {
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
        .accessibilityIdentifier(
            "timeline.record.\(taskVisual.symbolName).\(segment.id.uuidString)"
        )
        .accessibilityHint(AppStrings.localized("tasks.openDetail"))
    }

    private func accessibilityContent(display: TrackedTimeDisplaySnapshot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            TaskIcon(visual: taskVisual, size: 24)

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
            pendingDeletionRequest = draft.baseline
        } label: {
            Label(AppStrings.localized("timeline.deleteSegment"), systemImage: "trash")
        }
    }

    private var pendingDeletionImpact: SegmentDeletionImpact {
        guard let pendingDeletionRequest else {
            return .historicalRecord
        }
        return SegmentDeletionImpact(baseline: pendingDeletionRequest)
    }

    private var deletionPresentation: Binding<Bool> {
        Binding {
            pendingDeletionRequest != nil
        } set: { isPresented in
            if isPresented == false {
                pendingDeletionRequest = nil
            }
        }
    }

    private func regularContent(display: TrackedTimeDisplaySnapshot) -> some View {
        HStack(spacing: 12) {
            TaskIcon(visual: taskVisual, size: 24)

            Text(timeRangeText(display: display))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: isCompact ? 82 : 120, alignment: .leading)

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
        HStack(alignment: .center, spacing: 10) {
            TaskIcon(visual: taskVisual, size: 24)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
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
        case .pomodoro: .blue
        case .manual: .orange
        default: .secondary
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
