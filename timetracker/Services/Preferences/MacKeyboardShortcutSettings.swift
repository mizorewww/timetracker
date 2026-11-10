#if os(macOS)
import Foundation
import MacKeyboardShortcuts
import Observation

@MainActor
@Observable
final class MacKeyboardShortcutSettings {
    static let maximumPayloadByteCount = 4096

    private struct Value: Equatable {
        var shortcut: KeyboardShortcuts.Shortcut?
    }

    private let defaults: UserDefaults
    private var values: [MacKeyboardShortcutAction: Value] = [:]
    private(set) var revision = 0

    init(defaults: UserDefaults? = nil) {
        let resolvedDefaults = defaults ?? AppDefaults.shared
        self.defaults = resolvedDefaults
        let overrides = Self.loadOverrides(from: resolvedDefaults)
        values = Dictionary(
            uniqueKeysWithValues: MacKeyboardShortcutAction.allCases.map { action in
                let shortcut: KeyboardShortcuts.Shortcut? = switch overrides?[action] {
                case .disabled:
                    nil
                case let .custom(custom):
                    custom
                case nil:
                    action.defaultShortcut
                }
                return (action, Value(shortcut: shortcut))
            }
        )
    }

    func shortcut(
        for action: MacKeyboardShortcutAction
    ) -> KeyboardShortcuts.Shortcut? {
        values[action]?.shortcut
    }

    var isUsingDefaults: Bool {
        MacKeyboardShortcutAction.allCases.allSatisfy {
            shortcut(for: $0) == $0.defaultShortcut
        }
    }

    @discardableResult
    func setShortcut(
        _ shortcut: KeyboardShortcuts.Shortcut?,
        for action: MacKeyboardShortcutAction
    ) -> Bool {
        if let shortcut {
            if MacKeyboardShortcutAction.validationError(for: shortcut) != nil {
                return false
            }
            if conflictingAction(for: shortcut, excluding: action) != nil {
                return false
            }
        }
        var overrides = Self.loadOverrides(from: defaults) ?? [:]
        if let shortcut {
            overrides[action] = action.defaultShortcut == shortcut
                ? nil
                : .custom(shortcut)
        } else if action.defaultShortcut == nil {
            overrides[action] = nil
        } else {
            overrides[action] = .disabled
        }
        do {
            try persist(overrides)
            values[action] = Value(shortcut: shortcut)
            revision += 1
            return true
        } catch {
            return false
        }
    }

    func resetAll() {
        defaults.removeObject(
            forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
        )
        values = Dictionary(
            uniqueKeysWithValues: MacKeyboardShortcutAction.allCases.map {
                ($0, Value(shortcut: $0.defaultShortcut))
            }
        )
        revision += 1
    }

    func conflictingAction(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding action: MacKeyboardShortcutAction
    ) -> MacKeyboardShortcutAction? {
        MacKeyboardShortcutAction.allCases.first {
            $0 != action && values[$0]?.shortcut == shortcut
        }
    }

    private func persist(
        _ overrides: [MacKeyboardShortcutAction: MacKeyboardShortcutStoredOverride]
    ) throws {
        guard !overrides.isEmpty else {
            defaults.removeObject(
                forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
            )
            return
        }
        let payload = MacKeyboardShortcutPayload(
            overrides: Dictionary(
                uniqueKeysWithValues: overrides.map {
                    ($0.key.rawValue, $0.value)
                }
            )
        )
        let data = try JSONEncoder().encode(payload)
        guard data.count <= Self.maximumPayloadByteCount else {
            throw MacKeyboardShortcutValidationError.unsupported
        }
        defaults.set(
            data,
            forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
        )
    }

    private static func loadOverrides(
        from defaults: UserDefaults
    ) -> [MacKeyboardShortcutAction: MacKeyboardShortcutStoredOverride]? {
        guard let storedValue = defaults.object(
            forKey: AppLocalPreferenceKey.macKeyboardShortcutOverrides
        ) else {
            return [:]
        }
        guard
            let data = storedValue as? Data,
            data.count <= maximumPayloadByteCount,
            let payload = try? JSONDecoder().decode(
                MacKeyboardShortcutPayload.self,
                from: data
            ),
            let overrides = payload.resolvedOverrides(),
            hasValidResolvedShortcuts(overrides)
        else {
            return nil
        }
        return overrides
    }

    private static func hasValidResolvedShortcuts(
        _ overrides: [MacKeyboardShortcutAction: MacKeyboardShortcutStoredOverride]
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
                MacKeyboardShortcutAction.isValidAssignment(shortcut),
                seen.insert(shortcut).inserted
            else {
                return false
            }
        }
        return true
    }
}
#endif
