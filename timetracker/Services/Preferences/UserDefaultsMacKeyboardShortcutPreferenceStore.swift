#if os(macOS)
import Foundation
import MacKeyboardShortcuts

@MainActor
protocol MacKeyboardShortcutPreferenceStoring: AnyObject {
    func shortcut(
        for action: MacKeyboardShortcutAction
    ) -> KeyboardShortcuts.Shortcut?
    func setStoredShortcut(
        _ shortcut: KeyboardShortcuts.Shortcut?,
        for action: MacKeyboardShortcutAction
    ) throws
    func resetStoredShortcuts()
}

@MainActor
final class UserDefaultsMacKeyboardShortcutPreferenceStore:
    MacKeyboardShortcutPreferenceStoring
{
    static let maximumPayloadByteCount = 4096

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? AppDefaults.shared
    }

    func shortcut(
        for action: MacKeyboardShortcutAction
    ) -> KeyboardShortcuts.Shortcut? {
        guard let overrides = loadOverrides() else {
            return action.defaultShortcut
        }

        guard let storedOverride = overrides[action] else {
            return action.defaultShortcut
        }
        switch storedOverride {
        case .disabled:
            return nil
        case let .custom(shortcut):
            return shortcut
        }
    }

    func setStoredShortcut(
        _ shortcut: KeyboardShortcuts.Shortcut?,
        for action: MacKeyboardShortcutAction
    ) throws {
        var overrides = loadOverrides() ?? [:]
        if let shortcut {
            overrides[action] = shortcut == action.defaultShortcut
                ? nil
                : .custom(shortcut)
        } else {
            overrides[action] = .disabled
        }
        try persist(overrides)
    }

    func resetStoredShortcuts() {
        defaults.removeObject(
            forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
        )
    }

    private func loadOverrides() -> [MacKeyboardShortcutAction:
        MacKeyboardShortcutStoredOverride]?
    {
        guard let storedValue = defaults.object(
            forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
        ) else {
            return [:]
        }
        guard
            let data = storedValue as? Data,
            data.count <= Self.maximumPayloadByteCount,
            let payload = try? decoder.decode(
                MacKeyboardShortcutPayload.self,
                from: data
            ),
            let overrides = payload.resolvedOverrides(),
            Self.hasValidResolvedShortcuts(overrides)
        else {
            return nil
        }
        return overrides
    }

    private func persist(
        _ overrides: [MacKeyboardShortcutAction:
            MacKeyboardShortcutStoredOverride]
    ) throws {
        guard !overrides.isEmpty else {
            resetStoredShortcuts()
            return
        }
        let payload = MacKeyboardShortcutPayload(
            overrides: Dictionary(
                uniqueKeysWithValues: overrides.map {
                    ($0.key.rawValue, $0.value)
                }
            )
        )
        let data = try encoder.encode(payload)
        guard data.count <= Self.maximumPayloadByteCount else {
            throw MacKeyboardShortcutValidationError.unsupported
        }
        defaults.set(
            data,
            forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
        )
    }

    private static func hasValidResolvedShortcuts(
        _ overrides: [MacKeyboardShortcutAction:
            MacKeyboardShortcutStoredOverride]
    ) -> Bool {
        var seen: Set<KeyboardShortcuts.Shortcut> = []
        for action in MacKeyboardShortcutAction.allCases {
            let shortcut: KeyboardShortcuts.Shortcut? = switch overrides[action] {
            case .disabled:
                nil
            case let .custom(custom):
                custom
            case nil:
                action.defaultShortcut
            }
            guard let shortcut else { continue }
            guard
                !MacKeyboardShortcutAction.reservedShortcuts.contains(shortcut),
                seen.insert(shortcut).inserted
            else {
                return false
            }
        }
        return true
    }
}
#endif
