#if os(iOS)
import SwiftUI
import UIKit

struct LiveActivitySettingsSection: View {
    let store: TimeTrackerStore
    @State private var coordinator: LiveActivityCoordinator

    @MainActor
    init(store: TimeTrackerStore) {
        self.init(store: store, coordinator: .shared)
    }

    @MainActor
    init(store: TimeTrackerStore, coordinator: LiveActivityCoordinator) {
        self.store = store
        _coordinator = State(initialValue: coordinator)
    }

    var body: some View {
        Section {
            SettingsStatusRow(presentation: statusPresentation)
                .accessibilityIdentifier(
                    "settings.liveActivity.status.\(statusIdentifierComponent)"
                )

            recoveryAction
        } header: {
            SettingsHeader(
                symbol: "livephoto",
                title: AppStrings.localized("liveActivity.settings.title")
            )
        } footer: {
            Text(.app("liveActivity.settings.footer"))
        }
    }

    @ViewBuilder
    private var recoveryAction: some View {
        switch recovery {
        case .openSettings:
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link(destination: settingsURL) {
                    SettingsActionLabel(
                        title: AppStrings.localized(
                            "liveActivity.settings.openSystemSettings"
                        ),
                        systemImage: "gearshape",
                        tint: .secondary
                    )
                }
                .accessibilityIdentifier("settings.liveActivity.openSystemSettings")
            }
        case .retryWhenForeground, .retry:
            Button(action: retry) {
                SettingsActionLabel(
                    title: AppStrings.localized("liveActivity.settings.retry"),
                    systemImage: "arrow.clockwise",
                    tint: .blue
                )
            }
            .accessibilityIdentifier("settings.liveActivity.retry")
        case .none:
            EmptyView()
        }
    }

    private var recovery: LiveActivityRecovery {
        guard case let .unavailable(failure) = coordinator.status else {
            return .none
        }
        return failure.recovery
    }

    private var statusPresentation: SettingsStatusPresentation {
        switch coordinator.status {
        case .ready:
            SettingsStatusPresentation(
                title: localizedStatus("ready", field: "title"),
                message: localizedStatus("ready", field: "message"),
                symbolName: "livephoto",
                tint: .blue
            )
        case .synchronizing:
            SettingsStatusPresentation(
                title: localizedStatus("synchronizing", field: "title"),
                message: localizedStatus("synchronizing", field: "message"),
                symbolName: "arrow.clockwise",
                tint: .blue,
                showsProgress: true
            )
        case .active:
            SettingsStatusPresentation(
                title: localizedStatus("active", field: "title"),
                message: localizedStatus("active", field: "message"),
                symbolName: "checkmark.circle.fill",
                tint: .green
            )
        case let .unavailable(failure):
            unavailablePresentation(failure)
        }
    }

    private func unavailablePresentation(
        _ failure: LiveActivityFailure
    ) -> SettingsStatusPresentation {
        let component = failureIdentifierComponent(failure)
        let symbolName: String
        let tint: Color
        switch failure {
        case .unsupported:
            symbolName = "iphone.slash"
            tint = .secondary
        case .denied:
            symbolName = "livephoto.slash"
            tint = .orange
        case .backgroundStart:
            symbolName = "arrow.forward.circle"
            tint = .orange
        case .capacity:
            symbolName = "rectangle.stack.badge.exclamationmark"
            tint = .orange
        case .configuration:
            symbolName = "exclamationmark.shield.fill"
            tint = .red
        case .payloadTooLarge:
            symbolName = "doc.badge.ellipsis"
            tint = .red
        case .removed:
            symbolName = "xmark.circle.fill"
            tint = .orange
        case .system:
            symbolName = "exclamationmark.triangle.fill"
            tint = .red
        }
        return SettingsStatusPresentation(
            title: localizedStatus(component, field: "title"),
            message: localizedStatus(component, field: "message"),
            symbolName: symbolName,
            tint: tint
        )
    }

    private var statusIdentifierComponent: String {
        switch coordinator.status {
        case .ready:
            "ready"
        case .synchronizing:
            "synchronizing"
        case .active:
            "active"
        case let .unavailable(failure):
            failureIdentifierComponent(failure)
        }
    }

    private func failureIdentifierComponent(
        _ failure: LiveActivityFailure
    ) -> String {
        switch failure {
        case .unsupported: "unsupported"
        case .denied: "denied"
        case .backgroundStart: "backgroundStart"
        case .capacity: "capacity"
        case .configuration: "configuration"
        case .payloadTooLarge: "payloadTooLarge"
        case .removed: "removed"
        case .system: "system"
        }
    }

    private func localizedStatus(_ status: String, field: String) -> String {
        AppStrings.localized("liveActivity.settings.status.\(status).\(field)")
    }

    private func retry() {
        coordinator.retryLatestDesiredState()
        store.syncLiveActivitiesIfAvailable()
    }
}
#endif
