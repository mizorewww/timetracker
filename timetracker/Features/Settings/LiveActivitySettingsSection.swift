#if os(iOS)
import SwiftUI
import UIKit

struct LiveActivitySettingsSection: View {
    private let coordinator = LiveActivityCoordinator.shared

    var body: some View {
        Section {
            SettingsStatusRow(presentation: statusPresentation)
                .accessibilityIdentifier("settings.liveActivity.status")

            switch coordinator.status {
            case .denied:
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
            case .removed, .failed:
                Button(action: coordinator.retry) {
                    SettingsActionLabel(
                        title: AppStrings.localized("liveActivity.settings.retry"),
                        systemImage: "arrow.clockwise",
                        tint: .blue
                    )
                }
                .accessibilityIdentifier("settings.liveActivity.retry")
            case .ready, .active:
                EmptyView()
            }
        } header: {
            SettingsHeader(
                symbol: "livephoto",
                title: AppStrings.localized("liveActivity.settings.title")
            )
        } footer: {
            Text(.app("liveActivity.settings.footer"))
        }
    }

    private var statusPresentation: SettingsStatusPresentation {
        let key: String
        let symbolName: String
        let tint: Color
        switch coordinator.status {
        case .ready:
            (key, symbolName, tint) = ("ready", "livephoto", .blue)
        case .active:
            (key, symbolName, tint) = ("active", "checkmark.circle.fill", .green)
        case .denied:
            (key, symbolName, tint) = ("denied", "livephoto.slash", .orange)
        case .removed:
            (key, symbolName, tint) = ("removed", "xmark.circle.fill", .orange)
        case .failed:
            (key, symbolName, tint) = ("system", "exclamationmark.triangle.fill", .red)
        }
        return SettingsStatusPresentation(
            title: AppStrings.localized("liveActivity.settings.status.\(key).title"),
            message: AppStrings.localized("liveActivity.settings.status.\(key).message"),
            symbolName: symbolName,
            tint: tint
        )
    }
}
#endif
