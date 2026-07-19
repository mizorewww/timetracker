import Foundation

@MainActor
protocol AppleHealthTimelinePreferenceStoring: AnyObject {
    var isTimelineEnabled: Bool { get set }
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
}
