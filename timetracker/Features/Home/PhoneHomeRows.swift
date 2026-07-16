#if os(iOS)
import SwiftUI

struct PhoneTodaySummaryRow: View {
    let store: TimeTrackerStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let snapshot = store.todayMetricsSnapshot(now: context.date)
            VStack(spacing: 12) {
                PhoneSummaryMetric(
                    title: AppStrings.grossTime,
                    value: DurationFormatter.compact(snapshot.grossSeconds),
                    systemImage: "square.stack.3d.up",
                    tint: .blue
                )

                if store.preferences.showGrossAndWallTogether {
                    Divider()
                    PhoneSummaryMetric(
                        title: AppStrings.wallTime,
                        value: DurationFormatter.compact(snapshot.wallSeconds),
                        systemImage: "timeline.selection",
                        tint: .green
                    )
                }
            }
        }
    }
}

struct PhoneSummaryMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(title)
                            .font(.headline)
                    } icon: {
                        AppRowIcon(systemImage: systemImage, tint: tint)
                    }
                    Text(value)
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    AppRowIcon(systemImage: systemImage, tint: tint)
                    Text(title)
                    Spacer(minLength: 12)
                    Text(value)
                        .font(.headline.monospacedDigit())
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PhoneQuickStartRow: View {
    let presentation: TaskIdentityPresentation
    let isRunning: Bool
    let start: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let text = presentation.text(for: .standard)
        Button(action: start) {
            HStack(alignment: .top, spacing: 12) {
                TaskIcon(visual: presentation.visual, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.primary)
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    if let secondary = text.secondary {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .foregroundStyle(
                        isRunning ? .red : (Color(hex: presentation.visual.colorHex) ?? .accentColor)
                    )
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text.primary)
        .accessibilityValue(
            isRunning ? AppStrings.localized("status.running") : (text.secondary ?? "")
        )
        .accessibilityHint(
            AppStrings.localized(isRunning ? "timer.task.stopHint" : "timer.task.startHint")
        )
    }
}
#endif
