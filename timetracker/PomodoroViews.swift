import SwiftUI

struct PomodoroView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
    @State private var targetRounds = 1

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if horizontalSizeClass != .compact {
                    header
                }

                if let run = store.activePomodoroRun {
                    ActivePomodoroCard(store: store, run: run)
                } else {
                    PomodoroSetupCard(
                        store: store,
                        focusMinutes: $focusMinutes,
                        breakMinutes: $breakMinutes,
                        targetRounds: $targetRounds
                    )
                }

                PomodoroLedgerCard(store: store)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .navigationTitle(AppStrings.pomodoro)
        .background(AppColors.background)
        .onAppear {
            applyDefaultPreferences()
        }
        .onChange(of: store.preferences) { _, _ in
            applyDefaultPreferences()
        }
    }

    private func applyDefaultPreferences() {
        focusMinutes = store.preferences.defaultFocusMinutes
        breakMinutes = store.preferences.defaultBreakMinutes
        targetRounds = max(1, store.preferences.defaultPomodoroRounds)
        if let preset = PomodoroPreset(rawValue: store.preferences.pomodoroDefaultMode), preset != .custom {
            focusMinutes = preset.focusMinutes
            breakMinutes = preset.breakMinutes
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.pomodoro)
                .font(.largeTitle.bold())
                .accessibilityIdentifier("pomodoro.title")
            Text(.app("pomodoro.header.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum PomodoroPreset: String, CaseIterable, Identifiable {
    case classic = "25 / 5"
    case deep = "50 / 10"
    case quick = "15 / 3"
    case custom = "custom"

    var id: String { rawValue }

    var focusSeconds: Int {
        focusMinutes * 60
    }

    var breakSeconds: Int {
        breakMinutes * 60
    }

    var focusMinutes: Int {
        switch self {
        case .classic: return 25
        case .deep: return 50
        case .quick: return 15
        case .custom: return 25
        }
    }

    var breakMinutes: Int {
        switch self {
        case .classic: return 5
        case .deep: return 10
        case .quick: return 3
        case .custom: return 5
        }
    }

    var title: String {
        switch self {
        case .classic: return AppStrings.localized("pomodoro.preset.classic")
        case .deep: return AppStrings.localized("pomodoro.preset.deep")
        case .quick: return AppStrings.localized("pomodoro.preset.quick")
        case .custom: return AppStrings.localized("pomodoro.custom")
        }
    }
}

private struct PomodoroSetupCard: View {
    @ObservedObject var store: TimeTrackerStore
    @Binding var focusMinutes: Int
    @Binding var breakMinutes: Int
    @Binding var targetRounds: Int

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 1
        formatter.maximum = 480
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(.app("pomodoro.beforeStart"))
                    .font(.headline)
                Text(.app("pomodoro.beforeStart.message"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker(AppStrings.localized("pomodoro.chooseTask"), selection: Binding<UUID?>(
                get: { store.selectedTaskID },
                set: { store.selectedTaskID = $0 }
            )) {
                Text(.app("pomodoro.chooseTask")).tag(UUID?.none)
                ForEach(store.tasks) { task in
                    Text(store.path(for: task)).tag(Optional(task.id))
                }
            }

            Menu(AppStrings.localized("pomodoro.applyPreset")) {
                ForEach(PomodoroPreset.allCases.filter { $0 != .custom }) { preset in
                    Button(preset.title) {
                        focusMinutes = preset.focusMinutes
                        breakMinutes = preset.breakMinutes
                    }
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    Text(.app("pomodoro.focus"))
                        .foregroundStyle(.secondary)
                    TextField(AppStrings.localized("pomodoro.minuteField"), value: $focusMinutes, formatter: numberFormatter)
                        .textFieldStyle(.roundedBorder)
                    Text(.app("pomodoro.minuteField"))
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text(.app("pomodoro.break"))
                        .foregroundStyle(.secondary)
                    TextField(AppStrings.localized("pomodoro.minuteField"), value: $breakMinutes, formatter: numberFormatter)
                        .textFieldStyle(.roundedBorder)
                    Text(.app("pomodoro.minuteField"))
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text(.app("pomodoro.rounds"))
                        .foregroundStyle(.secondary)
                    TextField(AppStrings.localized("pomodoro.roundField"), value: $targetRounds, formatter: numberFormatter)
                        .textFieldStyle(.roundedBorder)
                    Text(.app("pomodoro.roundUnit"))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                PomodoroPlanMetric(title: AppStrings.localized("pomodoro.focus"), value: String(format: AppStrings.localized("common.minutes"), focusMinutes))
                PomodoroPlanMetric(title: AppStrings.localized("pomodoro.break"), value: String(format: AppStrings.localized("common.minutes"), breakMinutes))
                PomodoroPlanMetric(title: AppStrings.localized("pomodoro.rounds"), value: "\(targetRounds)")
            }

            Button {
                store.startPomodoroForSelectedTask(
                    focusSeconds: max(1, focusMinutes) * 60,
                    breakSeconds: max(1, breakMinutes) * 60,
                    targetRounds: max(1, targetRounds)
                )
            } label: {
                Label(AppStrings.localized("pomodoro.startFocus"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.selectedTaskID == nil)
            .accessibilityIdentifier("pomodoro.startFocus")
        }
        .padding(18)
        .appCard(padding: 0)
    }
}

private struct ActivePomodoroCard: View {
    @ObservedObject var store: TimeTrackerStore
    let run: PomodoroRun

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = store.pomodoroRemainingSeconds(for: run, now: context.date)
            let progress = store.pomodoroProgress(for: run, now: context.date)
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Label(store.pomodoroStateLabel(for: run), systemImage: run.state == .focusing ? "flame.fill" : "pause.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(run.state == .focusing ? .blue : .orange)
                    Text(store.taskTitle(for: run))
                        .font(.title2.weight(.semibold))
                    Text("\(run.completedFocusRounds) / \(run.targetRounds) \(AppStrings.localized("pomodoro.roundUnit"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 6) {
                        Text(DurationFormatter.clock(remaining))
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(remaining == 0 ? AppStrings.localized("pomodoro.canCompleteRound") : AppStrings.localized("pomodoro.remaining"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 240, height: 240)

                HStack(spacing: 12) {
                    if run.state == .interrupted,
                       let sessionID = run.sessionID,
                       let session = store.sessions.first(where: { $0.id == sessionID }) {
                        Button {
                            store.resume(session: session)
                        } label: {
                            Label(AppStrings.localized("pomodoro.resumeFocus"), systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            store.completeActivePomodoro()
                        } label: {
                            Label(remaining == 0 ? AppStrings.localized("pomodoro.action.completeRound") : AppStrings.localized("pomodoro.finishEarly"), systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button(role: .destructive) {
                        store.cancelActivePomodoro()
                    } label: {
                        Label(AppStrings.cancel, systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
            .appCard(padding: 0)
            .accessibilityIdentifier("pomodoro.active")
        }
    }
}

private struct PomodoroPlanMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PomodoroLedgerCard: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(.app("pomodoro.recent"))
                .font(.headline)

            if store.pomodoroRuns.isEmpty {
                EmptyStateRow(title: AppStrings.localized("pomodoro.empty"), icon: "timer")
            } else {
                VStack(spacing: 0) {
                    ForEach(store.pomodoroRuns.prefix(5)) { run in
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: run.state))
                                .foregroundStyle(color(for: run.state))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.taskTitle(for: run))
                                    .font(.subheadline.weight(.medium))
                                Text("\(store.pomodoroStateLabel(for: run)) · \(run.completedFocusRounds)/\(run.targetRounds) \(AppStrings.localized("pomodoro.roundUnit"))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(DurationFormatter.compact(run.focusSecondsPlanned))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)

                        if run.id != store.pomodoroRuns.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(18)
        .appCard(padding: 0)
    }

    private func iconName(for state: PomodoroState) -> String {
        switch state {
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .focusing: return "flame.fill"
        case .shortBreak, .longBreak: return "cup.and.saucer.fill"
        case .planned: return "timer"
        case .interrupted: return "pause.circle.fill"
        }
    }

    private func color(for state: PomodoroState) -> Color {
        switch state {
        case .completed: return .green
        case .cancelled: return .red
        case .focusing: return .blue
        case .shortBreak, .longBreak: return .orange
        case .planned, .interrupted: return .secondary
        }
    }
}
