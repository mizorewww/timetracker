import SwiftUI

extension SettingsView {
    var currentStorageValue: String {
        store.preferences.cloudSyncEnabled
            ? (store.syncStatus.isCloudBacked ? "iCloud" : AppStrings.localized("settings.localWillRetryCloud"))
            : AppStrings.localized("settings.local")
    }

    var syncFeedback: SyncFeedback {
        if store.pendingSyncConflict != nil {
            return SyncFeedback(
                state: .conflict,
                title: AppStrings.localized("sync.state.conflict.title"),
                message: AppStrings.localized("sync.state.conflict.message")
            )
        }
        return store.syncStatus.feedback(
            preferences: store.preferences,
            isChecking: isCheckingSync,
            lastRefreshAt: store.lastSyncRefreshAt
        )
    }

    func checkSyncStatus() {
        isCheckingSync = true
        Task {
            await store.refreshCloudAccountStatus()
            syncCheckMessage = store.syncStatus.accountStatus
            isCheckingSync = false
        }
    }

    func forceSyncRefresh() {
        isCheckingSync = true
        Task {
            syncCheckMessage = await store.forceCloudSyncRefresh()
            isCheckingSync = false
        }
    }

    func fetchLLMModels() {
        let endpoint = store.preferences.llmEndpoint
        let apiKey = store.preferences.llmAPIKey
        isFetchingLLMModels = true
        llmModelFetchMessage = nil

        Task {
            do {
                let models = try await LLMModelService().fetchModels(endpoint: endpoint, apiKey: apiKey)
                await MainActor.run {
                    store.setLLMAvailableModelIDs(models)
                    if !models.contains(store.preferences.llmSelectedModel) {
                        store.setLLMSelectedModel(models.first ?? "")
                    }
                    llmModelFetchMessage = String(format: AppStrings.localized("settings.llm.fetchSuccess"), models.count)
                    isFetchingLLMModels = false
                }
            } catch {
                await MainActor.run {
                    llmModelFetchMessage = String(format: AppStrings.localized("settings.llm.fetchFailed"), error.localizedDescription)
                    isFetchingLLMModels = false
                }
            }
        }
    }

    func fetchLLMModelsIfNeeded() {
        guard !isFetchingLLMModels,
              store.preferences.llmAvailableModelIDs.isEmpty,
              !store.preferences.llmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !store.preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        fetchLLMModels()
    }

    var syncCheckPresented: Binding<Bool> {
        Binding {
            syncCheckMessage != nil
        } set: { isPresented in
            if !isPresented {
                syncCheckMessage = nil
            }
        }
    }

    var optimizationMessagePresented: Binding<Bool> {
        Binding {
            databaseOptimizationMessage != nil
        } set: { isPresented in
            if !isPresented {
                databaseOptimizationMessage = nil
            }
        }
    }
}
