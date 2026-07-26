import SwiftUI

extension LLMReasoningEffort {
    var localizationKey: String {
        "settings.llm.reasoningEffort.\(rawValue)"
    }
}

struct LLMConfigurationDraft: Equatable {
    var endpoint: String
    var apiKey: String
    var selectedModel: String
    var availableModels: [String]
    var reasoningEffort: LLMReasoningEffort

    var normalized: Self {
        let normalizedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModels = Array(Set(availableModels.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
        let normalizedSelection = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(
            endpoint: normalizedEndpoint,
            apiKey: normalizedKey,
            selectedModel: normalizedModels.contains(normalizedSelection) ? normalizedSelection : "",
            availableModels: normalizedModels,
            reasoningEffort: reasoningEffort
        )
    }

    var credentialFingerprint: String {
        "\(endpoint.trimmingCharacters(in: .whitespacesAndNewlines))\u{0}\(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    var canSave: Bool {
        let normalizedDraft = normalized
        return LLMModelService.modelsURL(endpoint: normalizedDraft.endpoint) != nil &&
            !normalizedDraft.apiKey.isEmpty &&
            normalizedDraft.availableModels.contains(normalizedDraft.selectedModel)
    }
}

struct LLMSettingsSection: View {
    let automaticSuggestionsEnabled: Binding<Bool>
    let endpoint: String
    let hasAPIKey: Bool
    let selectedModel: String
    let availableModels: [String]
    let reasoningEffort: LLMReasoningEffort
    let onConfigure: () -> Void
    let onEditPrompt: (LLMPromptKind) -> Void

    private var isConfigured: Bool {
        LLMModelService.modelsURL(endpoint: endpoint) != nil &&
            hasAPIKey &&
            availableModels.contains(selectedModel)
    }

    var body: some View {
        Section {
            Button(action: onConfigure) {
                SettingsActionLabel(
                    title: AppStrings.localized("settings.llm.configure"),
                    systemImage: "slider.horizontal.3",
                    tint: .purple
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.llm.configure")

            ForEach(LLMPromptKind.allCases) { kind in
                Button {
                    onEditPrompt(kind)
                } label: {
                    SettingsActionLabel(
                        title: AppStrings.localized(kind.settingsEditTitleKey),
                        systemImage: kind.settingsSystemImage,
                        tint: kind.settingsTint
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(kind.settingsAccessibilityID).edit")
            }

            SettingsValueRow(
                title: AppStrings.localized("settings.llm.connection"),
                value: AppStrings.localized(isConfigured ? "settings.llm.ready" : "settings.llm.needsSetup"),
                systemImage: isConfigured ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                tint: isConfigured ? .green : .orange
            )

            if isConfigured {
                SettingsValueRow(
                    title: AppStrings.localized("settings.llm.model"),
                    value: selectedModel,
                    systemImage: "cpu",
                    tint: .indigo
                )

                SettingsValueRow(
                    title: AppStrings.localized(
                        "settings.llm.reasoningEffort"
                    ),
                    value: AppStrings.localized(
                        reasoningEffort.localizationKey
                    ),
                    systemImage: "brain.head.profile",
                    tint: .purple
                )
            }

            Toggle(isOn: automaticSuggestionsEnabled) {
                SettingsRowLabel(
                    title: AppStrings.localized("settings.llm.automaticSuggestions"),
                    systemImage: "sparkles",
                    tint: .purple
                )
            }
            .disabled(!isConfigured)
        } header: {
            SettingsHeader(symbol: "sparkles", title: AppStrings.localized("settings.llm"))
        } footer: {
            Text(.app("settings.llm.footer"))
        }
    }
}
