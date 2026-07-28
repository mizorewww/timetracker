#if os(macOS)
import AppKit
import MacKeyboardShortcuts

enum MacKeyboardShortcutGroup: String, CaseIterable, Identifiable, Sendable {
    case creation
    case timing
    case organization
    case navigation
    case data

    var id: Self {
        self
    }

    var title: String {
        AppStrings.localized(
            "settings.keyboardShortcuts.group.\(rawValue)"
        )
    }

    var actions: [MacKeyboardShortcutAction] {
        MacKeyboardShortcutAction.allCases.filter { $0.group == self }
    }
}

enum MacKeyboardShortcutAction:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case addTime
    case chooseTaskToStart
    case startSelectedTask
    case stopSelectedTask
    case addSubtask
    case startPomodoro
    case archiveSelectedTask
    case newTaskCategory
    case sortTaskCategories
    case generateTaskPlan
    case navigateToday
    case navigateInbox
    case navigateTasks
    case navigatePomodoro
    case navigateAnalytics
    case refreshData

    var id: Self {
        self
    }

    var defaultShortcut: KeyboardShortcuts.Shortcut? {
        switch self {
        case .addTime:
            KeyboardShortcuts.Shortcut(.m, modifiers: [.command, .shift])
        case .chooseTaskToStart,
             .stopSelectedTask,
             .addSubtask,
             .archiveSelectedTask,
             .newTaskCategory,
             .sortTaskCategories,
             .generateTaskPlan:
            nil
        case .startSelectedTask:
            KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .shift])
        case .startPomodoro:
            KeyboardShortcuts.Shortcut(.p, modifiers: [.command, .shift])
        case .navigateToday:
            KeyboardShortcuts.Shortcut(.one, modifiers: [.command])
        case .navigateInbox:
            KeyboardShortcuts.Shortcut(.two, modifiers: [.command])
        case .navigateTasks:
            KeyboardShortcuts.Shortcut(.three, modifiers: [.command])
        case .navigatePomodoro:
            KeyboardShortcuts.Shortcut(.four, modifiers: [.command])
        case .navigateAnalytics:
            KeyboardShortcuts.Shortcut(.five, modifiers: [.command])
        case .refreshData:
            KeyboardShortcuts.Shortcut(.r, modifiers: [.command])
        }
    }

    var group: MacKeyboardShortcutGroup {
        switch self {
        case .addTime,
             .chooseTaskToStart,
             .addSubtask,
             .newTaskCategory:
            .creation
        case .startSelectedTask,
             .stopSelectedTask,
             .startPomodoro:
            .timing
        case .archiveSelectedTask,
             .sortTaskCategories,
             .generateTaskPlan:
            .organization
        case .navigateToday,
             .navigateInbox,
             .navigateTasks,
             .navigatePomodoro,
             .navigateAnalytics:
            .navigation
        case .refreshData:
            .data
        }
    }

    var title: String {
        switch self {
        case .addTime:
            AppStrings.addTime
        case .chooseTaskToStart:
            AppStrings.localized("menu.chooseTaskToStart")
        case .startSelectedTask:
            AppStrings.localized("menu.startSelectedTask")
        case .stopSelectedTask:
            AppStrings.localized("menu.stopSelectedTask")
        case .addSubtask:
            AppStrings.localized("menu.addSubtask")
        case .startPomodoro:
            AppStrings.localized("menu.startPomodoro")
        case .archiveSelectedTask:
            AppStrings.localized("menu.archiveSelectedTask")
        case .newTaskCategory:
            AppStrings.localized("taskCategory.new")
        case .sortTaskCategories:
            AppStrings.localized("taskCategory.sort")
        case .generateTaskPlan:
            AppStrings.localized("aiTaskPlan.generateMenu")
        case .navigateToday:
            AppStrings.today
        case .navigateInbox:
            AppStrings.inbox
        case .navigateTasks:
            AppStrings.tasks
        case .navigatePomodoro:
            AppStrings.focus
        case .navigateAnalytics:
            AppStrings.analytics
        case .refreshData:
            AppStrings.localized("menu.refreshData")
        }
    }

    static let reservedShortcuts: Set<KeyboardShortcuts.Shortcut> = [
        KeyboardShortcuts.Shortcut(.n, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.comma, modifiers: [.command]),
    ]

    static let standaloneFunctionKeys: Set<KeyboardShortcuts.Key> = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
        .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
    ]

    static func isValidAssignment(
        _ shortcut: KeyboardShortcuts.Shortcut
    ) -> Bool {
        validationError(for: shortcut) == nil
    }

    static func validationError(
        for shortcut: KeyboardShortcuts.Shortcut
    ) -> MacKeyboardShortcutValidationError? {
        guard shortcut.toSwiftUI != nil,
              !shortcut.modifiers.isEmpty ||
              shortcut.key.map(standaloneFunctionKeys.contains) == true
        else {
            return .unsupported
        }
        guard reservedShortcuts.contains(shortcut) == false,
              shortcut.isTakenBySystem == false
        else {
            return .reserved
        }
        return nil
    }
}

enum MacKeyboardShortcutStoredOverride: Codable, Equatable {
    case disabled
    case custom(KeyboardShortcuts.Shortcut)
}

struct MacKeyboardShortcutPayload: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var overrides: [String: MacKeyboardShortcutStoredOverride] = [:]

    func resolvedOverrides() -> [MacKeyboardShortcutAction:
        MacKeyboardShortcutStoredOverride]?
    {
        guard schemaVersion == Self.currentSchemaVersion else {
            return nil
        }

        var resolved: [MacKeyboardShortcutAction:
            MacKeyboardShortcutStoredOverride] = [:]
        for (rawAction, override) in overrides {
            guard let action = MacKeyboardShortcutAction(rawValue: rawAction) else {
                continue
            }
            if case let .custom(shortcut) = override,
               shortcut.toSwiftUI == nil
            {
                return nil
            }
            resolved[action] = override
        }
        return resolved
    }
}

enum MacKeyboardShortcutValidationError: Error, Equatable {
    case duplicate(MacKeyboardShortcutAction)
    case reserved
    case unsupported
}
#endif
