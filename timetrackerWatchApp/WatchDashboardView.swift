import SwiftUI

struct WatchDashboardView: View {
    let snapshot: WatchStateSnapshot
    let isReachable: Bool
    let onStopTimer: (UUID) -> Void
    let onStartTask: (UUID) -> Void

    var body: some View {
        TabView {
            WatchTaskShortcutsPage(
                snapshot: snapshot,
                onToggleTask: toggleTask
            )

            WatchRunningPage(
                activeTimers: snapshot.activeTimers,
                isReachable: isReachable,
                onToggleTimer: { onStopTimer($0.id) }
            )
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
    }

    private func toggleTask(_ task: WatchRecentTaskSnapshot) {
        if let activeTimer = snapshot.activeTimers.first(where: { $0.taskID == task.taskID }) {
            onStopTimer(activeTimer.id)
        } else {
            onStartTask(task.taskID)
        }
    }
}

private struct WatchTaskShortcutsPage: View {
    let snapshot: WatchStateSnapshot
    let onToggleTask: (WatchRecentTaskSnapshot) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if snapshot.recentTasks.isEmpty {
                        WatchEmptyState(
                            title: String(localized: "watch.tasks.empty.title"),
                            message: String(localized: "watch.tasks.empty.message"),
                            systemImage: "rectangle.stack.badge.play"
                        )
                    } else {
                        ForEach(snapshot.recentTasks) { task in
                            let activeTimer = snapshot.activeTimers.first(where: { $0.taskID == task.taskID })
                            WatchTaskShortcutCard(
                                task: task,
                                activeTimer: activeTimer,
                                action: { onToggleTask(task) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .navigationTitle("watch.tasks.title")
        }
    }
}

private struct WatchRunningPage: View {
    let activeTimers: [WatchActiveTimerSnapshot]
    let isReachable: Bool
    let onToggleTimer: (WatchActiveTimerSnapshot) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    WatchReachabilityCard(isReachable: isReachable)

                    if activeTimers.isEmpty {
                        WatchEmptyState(
                            title: String(localized: "watch.running.empty.title"),
                            message: String(localized: "watch.running.empty.message"),
                            systemImage: "timer"
                        )
                    } else {
                        ForEach(activeTimers) { timer in
                            WatchActiveTimerCard(
                                timer: timer,
                                action: { onToggleTimer(timer) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .navigationTitle("watch.running.title")
        }
    }
}

private struct WatchTaskShortcutCard: View {
    let task: WatchRecentTaskSnapshot
    let activeTimer: WatchActiveTimerSnapshot?
    let action: () -> Void

    private var tint: Color {
        Color(hex: task.colorHex) ?? .blue
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                WatchIconTile(
                    systemImage: task.iconName ?? "play.fill",
                    tint: tint,
                    isRunning: activeTimer != nil
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !task.path.isEmpty {
                        Text(task.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("watch.tasks.noParent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 2)

                if activeTimer != nil {
                    Image(systemName: "stop.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.leading, 7)
            .padding(.trailing, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(activeTimer == nil ? .clear : tint.opacity(0.55), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.title)
        .accessibilityHint(activeTimer == nil ? Text("watch.tasks.startHint") : Text("watch.tasks.stopHint"))
    }
}

private struct WatchActiveTimerCard: View {
    let timer: WatchActiveTimerSnapshot
    let action: () -> Void

    private var tint: Color {
        Color(hex: timer.colorHex) ?? .blue
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    WatchIconTile(
                        systemImage: timer.iconName ?? "timer",
                        tint: tint,
                        isRunning: true
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(timer.title)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if !timer.path.isEmpty {
                            Text(timer.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "stop.fill")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                }

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(timer.startedAt, style: .timer)
                        .font(.title2.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(timer.title)
        .accessibilityHint(Text("watch.tasks.stopHint"))
    }
}

private struct WatchReachabilityCard: View {
    let isReachable: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isReachable ? "iphone.gen3.radiowaves.left.and.right" : "tray.and.arrow.up")
                .font(.headline)
                .foregroundStyle(isReachable ? .green : .yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(.init(isReachable ? "watch.status.reachable" : "watch.status.queued"))
                    .font(.caption.weight(.semibold))
                Text(.init(isReachable ? "watch.status.reachable.message" : "watch.status.queued.message"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct WatchIconTile: View {
    let systemImage: String
    let tint: Color
    let isRunning: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tint.opacity(isRunning ? 0.22 : 0.14))
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .symbolVariant(isRunning ? .fill : .none)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(width: 42, height: 48)
    }
}

private struct WatchEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
