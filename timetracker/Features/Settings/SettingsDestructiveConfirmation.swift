import SwiftUI

enum SettingsDestructiveConfirmation: Hashable {
    case rebuildDemo
    case clearDemo
    case resetAllData

    var titleKey: String {
        switch self {
        case .rebuildDemo: "dialog.rebuildDemo.title"
        case .clearDemo: "dialog.clearDemo.title"
        case .resetAllData: "dialog.resetData.title"
        }
    }

    var confirmKey: String {
        switch self {
        case .rebuildDemo: "dialog.rebuildDemo.confirm"
        case .clearDemo: "dialog.clearDemo.confirm"
        case .resetAllData: "dialog.resetData.confirm"
        }
    }

    var messageKey: String {
        switch self {
        case .rebuildDemo: "dialog.rebuildDemo.message"
        case .clearDemo: "dialog.clearDemo.message"
        case .resetAllData: "dialog.resetData.message"
        }
    }
}

extension SettingsView {
    var destructiveConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDestructiveConfirmation != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDestructiveConfirmation = nil
                }
            }
        )
    }

    func performDestructiveConfirmation(_ confirmation: SettingsDestructiveConfirmation) {
        switch confirmation {
        case .rebuildDemo:
            #if DEBUG
            feedbackRouter.perform { try store.replaceWithDemoData() }
            #endif
        case .clearDemo:
            #if DEBUG
            feedbackRouter.perform { try store.clearDemoData() }
            #endif
        case .resetAllData:
            feedbackRouter.perform { try store.clearAllData() }
        }
    }
}
