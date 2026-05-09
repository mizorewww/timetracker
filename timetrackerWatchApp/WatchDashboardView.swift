import SwiftUI

struct WatchDashboardView: View {
    let snapshot: WatchStateSnapshot
    let isReachable: Bool
    let onStopTimer: (UUID) -> Void
    let onStartTask: (UUID) -> Void

    var body: some View {
        NavigationStack {
            List {
                if snapshot.activeTimers.isEmpty {
                    Section {
                        ContentUnavailableView(
                            String(localized: "watch.empty.title"),
                            systemImage: "timer",
                            description: Text("watch.empty.message")
                        )
                    }
                } else {
                    Section(String(localized: "watch.active.title")) {
                        ForEach(snapshot.activeTimers) { timer in
                            activeTimerRow(timer)
                        }
                    }
                }

                if !snapshot.recentTasks.isEmpty {
                    Section(String(localized: "watch.recent.title")) {
                        ForEach(snapshot.recentTasks) { task in
                            Button {
                                onStartTask(task.taskID)
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title)
                                            .lineLimit(1)
                                        if !task.path.isEmpty {
                                            Text(task.path)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: task.iconName ?? "play.circle")
                                        .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Label(
                            isReachable ? String(localized: "watch.status.reachable") : String(localized: "watch.status.queued"),
                            systemImage: isReachable ? "iphone.gen3.radiowaves.left.and.right" : "tray.and.arrow.up"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("watch.title")
        }
    }

    private func activeTimerRow(_ timer: WatchActiveTimerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.title)
                        .font(.headline)
                        .lineLimit(1)
                    if !timer.path.isEmpty {
                        Text(timer.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } icon: {
                Image(systemName: timer.iconName ?? "timer")
                    .foregroundStyle(Color(hex: timer.colorHex) ?? .blue)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timer.startedAt, style: .timer)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.primary)
                    .accessibilityLabel(Text("watch.elapsed.accessibility"))
            }

            Button(role: .destructive) {
                onStopTimer(timer.id)
            } label: {
                Label("watch.stop", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

private extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if value.count == 3 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard value.count == 6, let integer = Int(value, radix: 16) else { return nil }
        self.init(
            red: Double((integer >> 16) & 0xFF) / 255,
            green: Double((integer >> 8) & 0xFF) / 255,
            blue: Double(integer & 0xFF) / 255
        )
    }
}
