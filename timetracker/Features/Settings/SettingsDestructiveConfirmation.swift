import SwiftUI

enum SettingsDestructiveConfirmation: Hashable {
    case rebuildDemo
    case clearDemo
    case resetAllData
    case optimizeDatabase

    var titleKey: String {
        switch self {
        case .rebuildDemo: "dialog.rebuildDemo.title"
        case .clearDemo: "dialog.clearDemo.title"
        case .resetAllData: "dialog.resetData.title"
        case .optimizeDatabase: "dialog.optimize.title"
        }
    }

    var confirmKey: String {
        switch self {
        case .rebuildDemo: "dialog.rebuildDemo.confirm"
        case .clearDemo: "dialog.clearDemo.confirm"
        case .resetAllData: "dialog.resetData.confirm"
        case .optimizeDatabase: "dialog.optimize.confirm"
        }
    }

    var messageKey: String {
        switch self {
        case .rebuildDemo: "dialog.rebuildDemo.message"
        case .clearDemo: "dialog.clearDemo.message"
        case .resetAllData: "dialog.resetData.message"
        case .optimizeDatabase: "dialog.optimize.message"
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
            store.replaceWithDemoData()
        case .clearDemo:
            store.clearDemoData()
        case .resetAllData:
            store.clearAllData()
        case .optimizeDatabase:
            dataOperationMessage = nil
            do {
                let removedCount = try store.optimizeDatabase()
                dataOperationMessage = removedCount == 0
                    ? AppStrings.localized("dialog.optimize.none")
                    : String(format: AppStrings.localized("dialog.optimize.removed"), removedCount)
            } catch {
                feedbackRouter.present(
                    context: .databaseMaintenance,
                    title: AppStrings.localized("settings.optimizeDatabase"),
                    message: String(
                        format: AppStrings.localized("dialog.optimize.failed"),
                        error.localizedDescription
                    )
                )
            }
        }
    }
}
