#if os(iOS)
import SwiftUI
import UIKit

struct AppleHealthTimelineSettingsSection: View {
    let store: TimeTrackerStore

    var body: some View {
        Section {
            Toggle(isOn: timelineVisibility) {
                SettingsRowLabel(
                    title: AppStrings.localized("health.settings.showInTimeline"),
                    systemImage: "figure.run",
                    tint: .pink
                )
            }
            .accessibilityIdentifier("settings.appleHealth.timelineToggle")
            .disabled(store.appleHealthTimelineState.isBusy)

            if let statusPresentation {
                SettingsStatusRow(presentation: statusPresentation)
            }

            if let taskSetupError = store.appleHealthTaskCatalogErrorMessage {
                SettingsStatusRow(
                    presentation: SettingsStatusPresentation(
                        title: AppStrings.localized(
                            "health.settings.taskSetupFailed.title"
                        ),
                        message: taskSetupError,
                        symbolName: "exclamationmark.triangle.fill",
                        tint: .orange
                    )
                )
            }

            if store.isAppleHealthTimelineEnabled,
               store.appleHealthTimelineState.isBusy == false
            {
                Button {
                    Task {
                        await store.refreshAppleHealthTimeline()
                    }
                } label: {
                    SettingsActionLabel(
                        title: AppStrings.localized("health.settings.refresh"),
                        systemImage: "arrow.clockwise",
                        tint: .blue
                    )
                }

                Button {
                    Task {
                        await store.showAppleHealthInTimeline()
                    }
                } label: {
                    SettingsActionLabel(
                        title: AppStrings.localized("health.timeline.reviewAccess"),
                        systemImage: "hand.raised",
                        tint: .orange
                    )
                }

                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link(destination: settingsURL) {
                        SettingsActionLabel(
                            title: AppStrings.localized("health.settings.openSystemSettings"),
                            systemImage: "gearshape",
                            tint: .secondary
                        )
                    }
                }
            }
        } header: {
            SettingsHeader(
                symbol: "heart.text.clipboard",
                title: AppStrings.localized("health.settings.title")
            )
        } footer: {
            Text(.app("health.settings.footer"))
        }
    }

    private var timelineVisibility: Binding<Bool> {
        Binding {
            store.isAppleHealthTimelineEnabled
        } set: { isEnabled in
            if isEnabled {
                Task {
                    await store.showAppleHealthInTimeline()
                }
            } else {
                store.hideAppleHealthFromTimeline()
            }
        }
    }

    private var statusPresentation: SettingsStatusPresentation? {
        switch store.appleHealthTimelineState {
        case .disabled:
            nil
        case .unavailable:
            SettingsStatusPresentation(
                title: AppStrings.localized("health.timeline.unavailable.title"),
                message: AppStrings.localized("health.timeline.unavailable.message"),
                symbolName: "heart.slash",
                tint: .secondary
            )
        case .ready:
            SettingsStatusPresentation(
                title: AppStrings.localized("health.timeline.ready.title"),
                message: AppStrings.localized("health.timeline.ready.message"),
                symbolName: "heart.text.clipboard",
                tint: .pink
            )
        case .requesting:
            SettingsStatusPresentation(
                title: AppStrings.localized("health.timeline.requesting"),
                message: AppStrings.localized("health.settings.requesting.message"),
                symbolName: "heart.text.clipboard",
                tint: .pink,
                showsProgress: true
            )
        case .loading:
            SettingsStatusPresentation(
                title: AppStrings.localized("health.timeline.loading"),
                message: AppStrings.localized("health.settings.loading.message"),
                symbolName: "heart.text.clipboard",
                tint: .pink,
                showsProgress: true
            )
        case let .content(_, refreshedAt, itemCount):
            SettingsStatusPresentation(
                title: String(
                    format: AppStrings.localized("health.settings.items.title"),
                    itemCount
                ),
                message: String(
                    format: AppStrings.localized("health.settings.lastRead"),
                    TimeDisplayFormatter.hourMinute(refreshedAt)
                ),
                symbolName: "checkmark.circle.fill",
                tint: .green
            )
        case let .noReadableData(_, refreshedAt):
            SettingsStatusPresentation(
                title: AppStrings.localized("health.timeline.empty.title"),
                message: String(
                    format: AppStrings.localized("health.settings.noData.lastRead"),
                    TimeDisplayFormatter.hourMinute(refreshedAt)
                ),
                symbolName: "heart.text.clipboard",
                tint: .secondary
            )
        case let .failed(message):
            SettingsStatusPresentation(
                title: AppStrings.localized("health.timeline.failed.title"),
                message: message,
                symbolName: "exclamationmark.triangle.fill",
                tint: .red
            )
        }
    }
}
#endif
