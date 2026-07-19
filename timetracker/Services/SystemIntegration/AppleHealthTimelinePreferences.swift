import Foundation

@MainActor
protocol AppleHealthTimelinePreferenceStoring: AnyObject {
    var isTimelineEnabled: Bool { get set }
    var taskCatalogClearRecoveryTaskIDs: Set<UUID> { get set }
}

@MainActor
final class UserDefaultsAppleHealthTimelinePreferenceStore:
    AppleHealthTimelinePreferenceStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isTimelineEnabled: Bool {
        get {
            defaults.bool(forKey: AppLocalPreferenceKey.appleHealthTimelineEnabled)
        }
        set {
            defaults.set(
                newValue,
                forKey: AppLocalPreferenceKey.appleHealthTimelineEnabled
            )
        }
    }

    var taskCatalogClearRecoveryTaskIDs: Set<UUID> {
        get {
            Set(
                defaults.stringArray(
                    forKey:
                        AppLocalPreferenceKey
                            .appleHealthTaskCatalogClearRecoveryTaskIDs
                )?.compactMap(UUID.init(uuidString:)) ?? []
            )
        }
        set {
            defaults.set(
                newValue.map(\.uuidString).sorted(),
                forKey:
                    AppLocalPreferenceKey
                        .appleHealthTaskCatalogClearRecoveryTaskIDs
            )
        }
    }
}
