import Combine
import SwiftUI

struct TaskDetailView: View {
    @ObservedObject var store: TimeTrackerStore
    let taskID: UUID
    @State private var range: AnalyticsRange = .week
    @State private var now = Date()
    @State private var draft: TaskEditorDraft?
    @State private var isEditorExpanded = false
    @FocusState private var focusedChecklistDraftID: UUID?
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let task = store.task(for: taskID) {
                detailContent(task: task)
            } else {
                EmptyStateRow(title: AppStrings.localized("task.empty.selectTask"), icon: "cursorarrow.click")
            }
        }
        .navigationTitle(store.task(for: taskID)?.title ?? AppStrings.localized("task.detail.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onReceive(refreshTimer) { date in
            now = date
        }
    }

    private func detailContent(task: TaskNode) -> some View {
        let snapshot = store.taskAnalyticsSnapshot(for: task, range: range, now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TaskDetailHeader(
                    store: store,
                    task: task,
                    snapshot: snapshot,
                    edit: { isEditorExpanded = true }
                )
                TaskDetailOverviewGrid(snapshot: snapshot)
                TaskDetailEditorCard(
                    store: store,
                    draft: detailDraftBinding(for: task),
                    isExpanded: $isEditorExpanded,
                    save: saveDraft,
                    reset: { resetDraft(for: task) },
                    focusedChecklistDraftID: $focusedChecklistDraftID
                )
                TaskForecastPanel(store: store, task: task)
                TaskDetailAnalysisSection(range: $range, snapshot: snapshot)
                TaskDetailRecentRecordsCard(records: snapshot.recentRecords)
            }
            .padding()
        }
        .background(AppColors.background)
        .onAppear {
            loadDraftIfNeeded(for: task)
        }
        .onChange(of: task.id) { _, _ in
            resetDraft(for: task)
        }
    }

    private func detailDraftBinding(for task: TaskNode) -> Binding<TaskEditorDraft> {
        Binding {
            if let draft, draft.taskID == task.id {
                return draft
            }
            return store.editorDraft(for: task)
        } set: { newValue in
            draft = newValue
        }
    }

    private func loadDraftIfNeeded(for task: TaskNode) {
        guard draft?.taskID != task.id else { return }
        draft = store.editorDraft(for: task)
    }

    private func resetDraft(for task: TaskNode) {
        draft = store.editorDraft(for: task)
    }

    private func saveDraft() {
        let draftToSave: TaskEditorDraft
        if let draft {
            draftToSave = draft
        } else if let task = store.task(for: taskID) {
            draftToSave = store.editorDraft(for: task)
        } else {
            return
        }

        if store.saveTaskDraft(draftToSave),
           let refreshedTask = store.task(for: taskID) {
            self.draft = store.editorDraft(for: refreshedTask)
        }
    }
}

private struct TaskDetailHeader: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    let snapshot: TaskAnalyticsSnapshot
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                TaskIcon(task: task, size: 42)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(task.title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                        if store.activeSegments.contains(where: { $0.taskID == task.id }) {
                            RunningStatusBadge()
                        } else {
                            TaskStatusBadge(status: task.status)
                        }
                    }

                    Text(store.path(for: task))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(action: edit) {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(AppStrings.localized("task.detail.editor.expand"))
            }

            HStack(spacing: 10) {
                Button {
                    store.startTask(task)
                } label: {
                    AppActionLabel(title: AppStrings.startTimer, systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.presentManualTime(taskID: task.id)
                } label: {
                    AppActionLabel(title: AppStrings.addTime, systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
            }

            if snapshot.overview.grossSeconds == 0 {
                Text(.app("task.detail.emptyAnalysis"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .appCard()
    }
}

private struct TaskDetailOverviewGrid: View {
    let snapshot: TaskAnalyticsSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            AnalyticsMetric(
                title: AppStrings.localized("task.field.total"),
                value: DurationFormatter.compact(snapshot.overview.grossSeconds),
                footnote: AppStrings.grossTime
            )
            AnalyticsMetric(
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(snapshot.overview.wallSeconds),
                footnote: AppStrings.localized("analytics.wall.footnote")
            )
            AnalyticsMetric(
                title: AppStrings.localized("task.detail.direct"),
                value: DurationFormatter.compact(snapshot.directSeconds),
                footnote: AppStrings.localized("task.detail.directFootnote")
            )
            AnalyticsMetric(
                title: AppStrings.localized("task.detail.children"),
                value: DurationFormatter.compact(snapshot.descendantSeconds),
                footnote: AppStrings.localized("task.detail.childrenFootnote")
            )
        }
    }
}

private struct TaskDetailAnalysisSection: View {
    @Binding var range: AnalyticsRange
    let snapshot: TaskAnalyticsSnapshot

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("task.detail.analysis"),
            subtitle: AppStrings.localized("task.detail.analysisSubtitle")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Picker(AppStrings.localized("analytics.range"), selection: $range) {
                    ForEach(AnalyticsRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if snapshot.overview.grossSeconds == 0 {
                    EmptyStateRow(title: AppStrings.localized("task.detail.emptyRange"), icon: "chart.bar")
                } else {
                    TaskDetailContributionBar(snapshot: snapshot)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        TaskDetailMetricCell(
                            title: AppStrings.localized("analytics.rhythm.averageSegment"),
                            value: DurationFormatter.compact(snapshot.rhythm.averageSegmentSeconds),
                            iconName: "timer"
                        )
                        TaskDetailMetricCell(
                            title: AppStrings.localized("analytics.rhythm.longest"),
                            value: DurationFormatter.compact(snapshot.rhythm.longestContinuousSeconds),
                            iconName: "arrow.left.and.right"
                        )
                        TaskDetailMetricCell(
                            title: AppStrings.localized("analytics.quality.switches"),
                            value: "\(snapshot.quality.switchCount)",
                            iconName: "arrow.triangle.swap"
                        )
                        TaskDetailMetricCell(
                            title: AppStrings.localized("analytics.quality.shortSegments"),
                            value: "\(snapshot.quality.shortSegmentCount)",
                            iconName: "scissors"
                        )
                    }

                    if !snapshot.childBreakdown.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(snapshot.childBreakdown) { item in
                                AnalyticsGroupBreakdownRowForTask(item: item, totalSeconds: max(snapshot.overview.grossSeconds, 1))
                                if item.id != snapshot.childBreakdown.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TaskDetailContributionBar: View {
    let snapshot: TaskAnalyticsSnapshot

    private var directRatio: CGFloat {
        CGFloat(snapshot.directSeconds) / CGFloat(max(snapshot.overview.grossSeconds, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.blue)
                        .frame(width: max(0, proxy.size.width * directRatio))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.green)
                        .frame(width: max(0, proxy.size.width * (1 - directRatio)))
                }
            }
            .frame(height: 14)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))

            HStack {
                AnalyticsLegendSwatch(color: .blue, title: AppStrings.localized("task.detail.direct"))
                AnalyticsLegendSwatch(color: .green, title: AppStrings.localized("task.detail.children"))
            }
        }
    }
}

private struct TaskDetailMetricCell: View {
    let title: String
    let value: String
    let iconName: String

    var body: some View {
        HStack(spacing: 10) {
            AppRowIcon(systemImage: iconName)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .appCard(padding: 12)
    }
}

private struct AnalyticsGroupBreakdownRowForTask: View {
    let item: AnalyticsGroupBreakdownPoint
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: item.colorHex) ?? .blue)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.compact(item.grossSeconds))
                    .font(.subheadline.monospacedDigit())
                Text("\(Int((Double(item.grossSeconds) / Double(max(totalSeconds, 1))) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
    }
}

private struct TaskDetailRecentRecordsCard: View {
    let records: [TaskRecentRecordPoint]

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("inspector.recentSessions"),
            subtitle: AppStrings.localized("task.detail.recentSubtitle")
        ) {
            if records.isEmpty {
                EmptyStateRow(title: AppStrings.localized("task.records.empty"), icon: "clock")
            } else {
                VStack(spacing: 0) {
                    ForEach(records) { record in
                        TaskDetailRecentRecordRow(record: record)
                        if record.id != records.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct TaskDetailRecentRecordRow: View {
    let record: TaskRecentRecordPoint

    var body: some View {
        HStack(spacing: 10) {
            AppRowIcon(systemImage: "clock", tint: .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(record.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.compact(record.durationSeconds))
                    .font(.subheadline.monospacedDigit())
                Text(timeRangeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 9)
    }

    private var timeRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "HH:mm"
        let end = record.endedAt.map { endFormatter.string(from: $0) } ?? AppStrings.localized("common.now")
        return "\(formatter.string(from: record.startedAt)) - \(end)"
    }
}
