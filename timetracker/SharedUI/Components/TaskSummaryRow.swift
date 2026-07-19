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
    case selected

    var isVisible: Bool {
        switch self {
        case .none:
            false
        case .selected:
            true
        }
    }
}

enum TaskSummaryRowLayout: Equatable {
    case stacked
    case inline
}

struct TaskSummaryRow: View {
    let presentation: TaskIdentityPresentation
    var context: TaskIdentityPresentation.Context = .standard
    var iconSize: CGFloat = 28
    var metadata: TaskSummaryRowMetadata?
    var layout: TaskSummaryRowLayout = .stacked
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let text = presentation.text(for: context)
        let activeLayout = resolvedLayout
        Group {
            switch activeLayout {
            case .stacked:
                stackedContent(text: text)
            case .inline:
                inlineContent(text: text)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: activeLayout == .stacked ? minimumRowHeight : nil,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }

    private func stackedContent(text: TaskIdentityText) -> some View {
        HStack(alignment: .top, spacing: 12) {
            TaskIcon(visual: presentation.visual, size: iconSize)

            VStack(alignment: .leading, spacing: 5) {
                identityText(
                    text,
                    primaryLineLimit: dynamicTypeSize.isAccessibilitySize ? nil : 2,
                    secondaryLineLimit: 2
                )

                if let metadata, metadata.isEmpty == false {
                    TaskSummaryMetadataLine(
                        metadata: metadata,
                        tint: Color(hex: presentation.visual.colorHex) ?? .accentColor,
                        layout: .stacked
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inlineContent(text: TaskIdentityText) -> some View {
        HStack(alignment: .center, spacing: 12) {
            TaskIcon(visual: presentation.visual, size: iconSize)

            VStack(alignment: .leading, spacing: 5) {
                identityText(
                    text,
                    primaryLineLimit: 1,
                    secondaryLineLimit: 1
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let metadata, metadata.isEmpty == false {
                TaskSummaryMetadataLine(
                    metadata: metadata,
                    tint: Color(hex: presentation.visual.colorHex) ?? .accentColor,
                    layout: .inline
                )
                .frame(minHeight: iconSize)
                .layoutPriority(2)
            }
        }
    }

    @ViewBuilder
    private func identityText(
        _ text: TaskIdentityText,
        primaryLineLimit: Int?,
        secondaryLineLimit: Int
    ) -> some View {
        Text(text.primary)
            .font(.body.weight(.medium))
            .lineLimit(primaryLineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

        if let secondary = text.secondary {
            Text(secondary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(secondaryLineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resolvedLayout: TaskSummaryRowLayout {
        layout == .inline && dynamicTypeSize.isAccessibilitySize
            ? .stacked
            : layout
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
