import SwiftUI

extension LLMPromptKind {
    var settingsTitleKey: String {
        "settings.llm.prompt.\(rawValue).title"
    }

    var settingsEditTitleKey: String {
        "settings.llm.prompt.\(rawValue).edit"
    }

    var settingsEditorTitleKey: String {
        "settings.llm.prompt.\(rawValue).editorTitle"
    }

    var settingsFooterKey: String {
        "settings.llm.prompt.\(rawValue).footer"
    }

    var settingsAccessibilityID: String {
        "settings.llm.prompt.\(rawValue)"
    }

    var settingsSystemImage: String {
        switch self {
        case .inboxRouting:
            "tray.and.arrow.down"
        case .checklistVisual:
            "paintpalette"
        case .taskPlan:
            "list.bullet.rectangle"
        }
    }

    var settingsTint: Color {
        switch self {
        case .inboxRouting:
            .purple
        case .checklistVisual:
            .teal
        case .taskPlan:
            .indigo
        }
    }
}
