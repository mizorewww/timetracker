import SwiftUI

struct PomodoroView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var focusMinutes = 25
    @State private var breakMinutes = 5
    @State private var targetRounds = 1

    private var layout: PomodoroLayoutPolicy {
        PomodoroLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if layout.showsInlineHeader {
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
