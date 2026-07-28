import SwiftUI

struct TimelineRow: View {
    let store: TimeTrackerStore
    let entry: AnalyticsTimelineEntry?
    let segment: TimeSegment
    var openTaskDetail: ((UUID) -> Void)?
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var pendingDeletionRequest: SegmentEditorDraftBaseline?

    init(
        store: TimeTrackerStore,
        entry: AnalyticsTimelineEntry? = nil,
        segment: TimeSegment,
        openTaskDetail: ((UUID) -> Void)? = nil
    ) {
        self.store = store
        self.entry = entry
        self.segment = segment
        self.openTaskDetail = openTaskDetail
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
            iconName: entry?.iconName ?? task?.iconName,
            colorHex: entry?.colorHex ?? task?.colorHex
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
        .modifier(TodayTimelineRecordInsets())
    }

    private func taskButton(at now: Date) -> some View {
        let startedAt = entry?.startedAt ?? segment.startedAt
        let endedAt = entry.map {
            $0.usesCurrentEndLabel ? nil : $0.endedAt
        } ?? segment.endedAt
        let displayNow = if let entry, entry.usesCurrentEndLabel == false {
            entry.endedAt
        } else {
            now
        }
        let display = TrackedTimeDisplaySnapshot(
            startedAt: startedAt,
            endedAt: endedAt,
            now: displayNow
        )
        let presentation = TodayTimelineRecordPresentation(
            id: entry?.id ?? .trackedSegment(segment.id),
            visual: taskVisual,
            title: displayTitle,
            sourceLabel: tag,
            sourceTint: tagColor,
            startedAt: display.start,
            endedAt: display.end,
            usesCurrentEndLabel: display.usesCurrentEndLabel,
            duration: .live(
                startedAt: startedAt,
                endedAt: endedAt
            )
        )

        return Button(action: openTask) {
            TodayTimelineRecordContent(presentation: presentation)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "timeline.record.\(taskVisual.symbolName).\(segment.id.uuidString)"
        )
        .accessibilityValue(presentation.timeRangeText)
        .accessibilityHint(AppStrings.localized("tasks.openDetail"))
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

    private var displayTitle: String {
        entry?.title ?? store.displayTitle(for: segment)
    }

    private var tagColor: Color {
        switch segment.source {
        case .pomodoro: .blue
        case .manual: .orange
        default: .secondary
        }
    }

    private func openTask() {
        if let openTaskDetail {
            openTaskDetail(segment.taskID)
        } else {
            store.openTaskDetail(segment.taskID)
        }
    }
}

enum TodayTimelineRecordDuration {
    case live(startedAt: Date, endedAt: Date?)
    case fixed(seconds: Int)
}

struct TodayTimelineRecordPresentation {
    let id: TimelineEntryID
    let visual: TaskVisualPresentation
    let title: String
    let sourceLabel: String
    let sourceTint: Color
    let startedAt: Date
    let endedAt: Date
    let usesCurrentEndLabel: Bool
    let duration: TodayTimelineRecordDuration

    var timeRangeText: String {
        let start = TimeDisplayFormatter.hourMinute(startedAt)
        let end = usesCurrentEndLabel
            ? AppStrings.localized("common.now")
            : TimeDisplayFormatter.hourMinute(endedAt)
        return "\(start) - \(end)"
    }

    var accessibilityPrefix: String {
        "home.timeline.entry.\(id.namespacedKey)"
    }
}

struct TodayTimelineRecordContent: View {
    let presentation: TodayTimelineRecordPresentation
    @Environment(\.layoutShell) private var layoutShell
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isCompact: Bool {
        layoutShell == .compact
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityContent
            } else if isCompact {
                compactContent
            } else {
                ViewThatFits(in: .horizontal) {
                    regularContent
                    compactContent
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var accessibilityContent: some View {
        HStack(alignment: .top, spacing: 10) {
            TaskIcon(visual: presentation.visual, size: 24)

            VStack(alignment: .leading, spacing: 8) {
                titleText
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                timeRangeText
                    .font(.footnote.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        sourceBadge
                        Spacer(minLength: 8)
                        durationText
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        sourceBadge
                        durationText
                    }
                }
            }
        }
    }

    private var regularContent: some View {
        HStack(spacing: 12) {
            TaskIcon(visual: presentation.visual, size: 24)

            timeRangeText
                .font(.subheadline.monospacedDigit())
                .frame(width: 120, alignment: .leading)

            titleText
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            sourceBadge
                .frame(width: 96, alignment: .center)

            durationText
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var compactContent: some View {
        HStack(alignment: .center, spacing: 10) {
            TaskIcon(visual: presentation.visual, size: 24)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    timeRangeText
                        .font(.footnote.monospacedDigit())
                        .lineLimit(1)
                    Spacer()
                    durationText
                }

                HStack(alignment: .center, spacing: 10) {
                    titleText
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    sourceBadge
                }
            }
        }
    }

    private var titleText: some View {
        Text(presentation.title)
            .foregroundStyle(.primary)
            .accessibilityIdentifier(
                "\(presentation.accessibilityPrefix).title"
            )
    }

    private var timeRangeText: some View {
        Text(presentation.timeRangeText)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(
                "\(presentation.accessibilityPrefix).timeRange"
            )
    }

    private var sourceBadge: some View {
        Text(presentation.sourceLabel)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(presentation.sourceTint)
            .background(
                presentation.sourceTint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .lineLimit(1)
            .accessibilityIdentifier(
                "\(presentation.accessibilityPrefix).source"
            )
    }

    private var durationText: some View {
        Group {
            switch presentation.duration {
            case let .live(startedAt, endedAt):
                DurationLabel(
                    startedAt: startedAt,
                    endedAt: endedAt
                )
            case let .fixed(seconds):
                Text(DurationFormatter.compact(seconds))
            }
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(presentation.usesCurrentEndLabel ? Color.blue : Color.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .accessibilityIdentifier(
            "\(presentation.accessibilityPrefix).duration"
        )
    }
}

struct TodayTimelineRecordInsets: ViewModifier {
    @Environment(\.layoutShell) private var layoutShell

    private var isCompact: Bool {
        layoutShell == .compact
    }

    func body(content: Content) -> some View {
        content
            .padding(.leading, 14)
            .padding(.trailing, isCompact ? 0 : 14)
            .padding(.vertical, isCompact ? 11 : 10)
    }
}
