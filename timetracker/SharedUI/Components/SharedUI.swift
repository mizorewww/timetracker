import SwiftData
import SwiftUI

struct SectionTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.blue)
            }
        }
    }
}

struct DurationLabel: View {
    let startedAt: Date
    let endedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let end = endedAt ?? context.date
            Text(DurationFormatter.clock(Int(end.timeIntervalSince(startedAt))))
        }
    }
}

struct EmptyStateRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: TimeTrackerModelRegistry.currentModels, inMemory: true)
}
