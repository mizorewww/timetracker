import SwiftUI

enum SettingsDestructiveConfirmation: Hashable {
    case rebuildDemo
    case clearDemo
    case resetAllData
    case optimizeDatabase
    case replaceCloud(expectedConflictID: UUID?)
    case replaceDevice(expectedConflictID: UUID?)

    var titleKey: String {
        switch self {
        case .rebuildDemo: "dialog.rebuildDemo.title"
        case .clearDemo: "dialog.clearDemo.title"
        case .resetAllData: "dialog.resetData.title"
        case .optimizeDatabase: "dialog.optimize.title"
        case .replaceCloud: "dialog.forceUpload.title"
        case .replaceDevice: "dialog.forceDownload.title"
        }
    }

    var confirmKey: String {
        switch self {
        case .rebuildDemo: "dialog.rebuildDemo.confirm"
        case .clearDemo: "dialog.clearDemo.confirm"
        case .resetAllData: "dialog.resetData.confirm"
        case .optimizeDatabase: "dialog.optimize.confirm"
        case .replaceCloud: "dialog.forceUpload.confirm"
        case .replaceDevice: "dialog.forceDownload.confirm"
        }
    }

    var messageKey: String {
        switch self {
        case .rebuildDemo: "dialog.rebuildDemo.message"
        case .clearDemo: "dialog.clearDemo.message"
        case .resetAllData: "dialog.resetData.message"
        case .optimizeDatabase: "dialog.optimize.message"
        case .replaceCloud: "dialog.forceUpload.message"
        case .replaceDevice: "dialog.forceDownload.message"
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
            let removedCount = store.optimizeDatabase()
            databaseOptimizationMessage = removedCount == 0
                ? AppStrings.localized("dialog.optimize.none")
                : String(format: AppStrings.localized("dialog.optimize.removed"), removedCount)
        case let .replaceCloud(expectedConflictID):
            forceUploadLocalData(expectedConflictID: expectedConflictID)
        case let .replaceDevice(expectedConflictID):
            forceDownloadCloudData(expectedConflictID: expectedConflictID)
        }
    }
}
