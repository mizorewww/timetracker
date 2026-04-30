import SwiftUI

struct CompactChecklistProgressLine: View {
    let progress: ChecklistProgress
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            ProgressView(value: progress.fraction)
                .tint(tint)
                .frame(maxWidth: 76)

            Text(String(format: AppStrings.localized("checklist.progressFormat"), progress.completedCount, progress.totalCount))
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

struct TaskProgressLine: View {
    let progress: ChecklistProgress
    let rollup: TaskRollup?
    var showsChecklist = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if showsChecklist {
                    checklistLabel
                }
                if let remainingText {
                    Text(remainingText)
                }
                if let daysText {
                    Text(daysText)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                if showsChecklist {
                    checklistLabel
                }
                if let remainingText {
                    Text(remainingText)
                }
                if let daysText {
                    Text(daysText)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var checklistLabel: some View {
        HStack(spacing: 5) {
            if progress.totalCount > 0 {
                ProgressView(value: progress.fraction)
                    .frame(width: 48)
                Text(String(format: AppStrings.localized("checklist.progressFormat"), progress.completedCount, progress.totalCount))
            } else {
                Text(AppStrings.localized("checklist.noItems"))
            }
        }
    }

    private var remainingText: String? {
        guard rollup?.isDisplayableForecast == true, let remaining = rollup?.remainingSeconds else { return nil }
        return String(format: AppStrings.localized("forecast.remainingFormat"), DurationFormatter.compact(remaining))
    }

    private var daysText: String? {
        guard rollup?.isDisplayableForecast == true, let rollup else { return nil }
        return rollup.projectedDaysDisplayText
    }
}
