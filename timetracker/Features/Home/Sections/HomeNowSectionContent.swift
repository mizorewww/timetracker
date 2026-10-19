import SwiftUI

/// Today's Now section: running timers plus the start-timer action, as a
/// grouped list section (compact) or a titled card (regular canvas).
struct HomeNowSection: View {
    let store: TimeTrackerStore
    let container: HomeSectionContainer
    let segments: [TimeSegment]
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    var body: some View {
        switch container {
        case .listSection:
            Section {
                if segments.isEmpty {
                    startTimerButton
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    activeContent(actionLabelStyle: .iconOnly)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            } header: {
                header
                    .textCase(nil)
            } footer: {
                if segments.isEmpty {
                    Text(.app("timer.chooseTaskFooter"))
                }
            }
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                header
                Group {
                    if segments.isEmpty {
                        startTimerButton
                    } else {
                        activeContent(actionLabelStyle: .titleAndIcon)
                    }
                }
                .appCard(padding: 0)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.now.card")
                if segments.isEmpty {
                    Text(.app("timer.chooseTaskFooter"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        HomeSectionHeader(
            container: container,
            title: AppStrings.localized("home.now.title"),
            accessibilityIdentifier: "home.activeTimers"
        ) {
            EmptyView()
        }
    }

    private var startTimerButton: some View {
        HomeTimerPickerButton(
            mode: store.timerPickerMode,
            action: startTimer,
            accessibilityIdentifier: "home.startTimer"
        )
    }

    private func activeContent(actionLabelStyle: TaskTimerActionLabelStyle) -> some View {
        HomeNowActiveContent(
            store: store,
            segments: segments,
            timerPickerMode: store.timerPickerMode,
            actionLabelStyle: actionLabelStyle,
            openTask: openTask,
            startTimer: startTimer
        )
    }
}

/// Shared Now content used by every platform: iPhone hosts it in a grouped
/// list section, iPad and macOS in an app card.
struct HomeNowActiveContent: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let timerPickerMode: TimerPickerMode
    let actionLabelStyle: TaskTimerActionLabelStyle
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(segments, id: \.id) { segment in
                ActiveTimerRow(
                    store: store,
                    segment: segment,
                    actionLabelStyle: actionLabelStyle,
                    openTaskDetail: openTask
                )
                .padding(12)
                .accessibilityIdentifier("home.activeTimer.\(segment.id.uuidString)")

                Divider()
                    .padding(.horizontal, 12)
            }

            HomeTimerPickerButton(
                mode: timerPickerMode,
                action: startTimer,
                accessibilityIdentifier: "home.startTimer"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeTimerPickerButton: View {
    let mode: TimerPickerMode
    let action: () -> Void
    let accessibilityIdentifier: String

    var body: some View {
        Button(action: action) {
            Label {
                Text(mode.title)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: mode.primaryActionSystemImage)
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
