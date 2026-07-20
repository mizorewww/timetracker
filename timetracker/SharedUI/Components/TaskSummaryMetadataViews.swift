import SwiftUI

struct TaskSummaryMetadataLine: View {
    let metadata: TaskSummaryRowMetadata
    let tint: Color
    let layout: TaskSummaryRowLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        switch layout {
        case .stacked:
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        checklistProgress
                        trailingFacts
                    }
                } else {
                    HStack(spacing: 8) {
                        checklistProgress
                        Spacer(minLength: 8)
                        trailingFacts
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            HStack(spacing: 8) {
                checklistProgress
                trailingFacts
            }
        }
    }

    @ViewBuilder
    private var checklistProgress: some View {
        if let progress = metadata.checklistProgress {
            CompactChecklistProgressLine(
                progress: progress,
                tint: tint,
                showsProgressBar: layout == .stacked
            )
        }
    }

    private var trailingFacts: some View {
        HStack(spacing: 8) {
            passiveStatusGroup

            if let workedSeconds = metadata.workedSeconds {
                Text(DurationFormatter.compact(workedSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if metadata.showsNavigationChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var passiveStatusGroup: some View {
        let statuses = TaskPickerPassiveStatus.activeStates(
            isRunning: metadata.isRunning,
            isSelected: metadata.accessory.isSelected
        )
        if statuses.isEmpty == false {
            TaskPickerPassiveStatusGroup(statuses: statuses)
        }
    }
}

enum TaskPickerPassiveStatus: CaseIterable, Hashable {
    case running
    case selected

    var systemImage: String {
        switch self {
        case .running:
            "timer.circle.fill"
        case .selected:
            "checkmark.circle.fill"
        }
    }

    static func activeStates(
        isRunning: Bool,
        isSelected: Bool
    ) -> [TaskPickerPassiveStatus] {
        var states: [TaskPickerPassiveStatus] = []
        if isRunning {
            states.append(.running)
        }
        if isSelected {
            states.append(.selected)
        }
        return states
    }
}

private struct TaskPickerPassiveStatusGroup: View {
    let statuses: [TaskPickerPassiveStatus]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(statuses, id: \.self) { status in
                switch status {
                case .running:
                    TaskRunningIndicator()
                case .selected:
                    TaskSelectedIndicator()
                }
            }
        }
    }
}

private struct TaskPickerPassiveStatusIcon: View {
    let status: TaskPickerPassiveStatus

    var body: some View {
        Image(systemName: status.systemImage)
            .symbolRenderingMode(.monochrome)
            .font(.caption.weight(.semibold))
            .imageScale(.medium)
            .foregroundStyle(status == .running ? Color.green : Color.accentColor)
            .frame(
                width: TaskPickerIndicatorMetrics.passiveSlotDimension,
                height: TaskPickerIndicatorMetrics.passiveSlotDimension
            )
    }
}

struct TaskRunningIndicator: View {
    var body: some View {
        TaskPickerPassiveStatusIcon(status: .running)
            .accessibilityLabel(AppStrings.running)
    }
}

private struct TaskSelectedIndicator: View {
    var body: some View {
        TaskPickerPassiveStatusIcon(status: .selected)
            .accessibilityHidden(true)
    }
}
