import SwiftUI

struct CompactChecklistProgressLine: View {
    let progress: ChecklistProgress
    let tint: Color
    var showsProgressBar = true

    var body: some View {
        HStack(spacing: 7) {
            if showsProgressBar {
                ProgressView(value: progress.fraction)
                    .tint(tint)
                    .frame(maxWidth: 76)
            }

            Text(String(format: AppStrings.localized("checklist.progressFormat"), progress.completedCount, progress.totalCount))
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
