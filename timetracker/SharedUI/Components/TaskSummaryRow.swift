import SwiftUI

struct TaskSummaryRowMetadata {
    var checklistProgress: ChecklistProgress? = nil
    var workedSeconds: Int? = nil
    var isRunning = false
    var showsNavigationChevron = false
    var accessory: TaskSummaryRowAccessory = .none

    var isEmpty: Bool {
        checklistProgress == nil
            && workedSeconds == nil
            && isRunning == false
            && showsNavigationChevron == false
            && accessory.isVisible == false
    }
}

enum TaskSummaryRowAccessory {
    case none
    case command(title: String, systemImage: String)
    case selected

    var isVisible: Bool {
        switch self {
        case .none:
            false
        case .command, .selected:
            true
        }
    }
}

struct TaskSummaryRow: View {
    let presentation: TaskIdentityPresentation
    var context: TaskIdentityPresentation.Context = .standard
    var iconSize: CGFloat = 28
    var metadata: TaskSummaryRowMetadata?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let text = presentation.text(for: context)
        HStack(alignment: .top, spacing: 12) {
            TaskIcon(visual: presentation.visual, size: iconSize)

            VStack(alignment: .leading, spacing: 5) {
                Text(text.primary)
                    .font(.body.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                if let secondary = text.secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let metadata, metadata.isEmpty == false {
                    TaskSummaryMetadataLine(
                        metadata: metadata,
                        tint: Color(hex: presentation.visual.colorHex) ?? .accentColor
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: minimumRowHeight,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }

    private var minimumRowHeight: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }
}

private struct TaskSummaryMetadataLine: View {
    let metadata: TaskSummaryRowMetadata
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
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
    }

    @ViewBuilder
    private var checklistProgress: some View {
        if let progress = metadata.checklistProgress {
            CompactChecklistProgressLine(
                progress: progress,
                tint: tint
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
        case let .command(title, systemImage):
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(minWidth: 24, minHeight: 24)
                .help(title)
                .accessibilityHidden(true)
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
