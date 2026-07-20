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
            if metadata.isRunning {
                TaskRunningIndicator()
            }

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

            accessory
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch metadata.accessory {
        case .none:
            EmptyView()
        case .selected:
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(minWidth: 24, minHeight: 24)
                .accessibilityHidden(true)
        }
    }
}

struct TaskRunningIndicator: View {
    var body: some View {
        Image(systemName: "timer")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.green)
            .accessibilityLabel(AppStrings.running)
    }
}
