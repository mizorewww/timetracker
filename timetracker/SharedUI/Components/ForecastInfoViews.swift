import SwiftUI

struct ForecastInfoButton: View {
    var body: some View {
        InformationPresentationButton(
            title: AppStrings.localized("forecast.info.title"),
            accessibilityIdentifier: "forecast.info.open"
        ) {
            ForecastInfoView()
                .frame(minWidth: 320, idealWidth: 420, maxWidth: 520, minHeight: 420)
        }
    }
}

struct ForecastInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    InformationGuideRow(
                        icon: "checklist",
                        title: AppStrings.localized("forecast.info.requirements.title"),
                        bodyText: AppStrings.localized("forecast.info.requirements.body")
                    )
                    .accessibilityIdentifier("home.info.forecast.requirements")
                    InformationGuideRow(
                        icon: "function",
                        title: AppStrings.localized("forecast.info.formula.title"),
                        bodyText: AppStrings.localized("forecast.info.formula.body")
                    )
                    .accessibilityIdentifier("home.info.forecast.formula")
                    InformationGuideRow(
                        icon: "folder.badge.gearshape",
                        title: AppStrings.localized("forecast.info.children.title"),
                        bodyText: AppStrings.localized("forecast.info.children.body")
                    )
                    .accessibilityIdentifier("home.info.forecast.children")
                    InformationGuideRow(
                        icon: "archivebox",
                        title: AppStrings.localized("forecast.info.history.title"),
                        bodyText: AppStrings.localized("forecast.info.history.body")
                    )
                    .accessibilityIdentifier("home.info.forecast.history")
                }

                Section(AppStrings.localized("forecast.info.example.title")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.localized("forecast.info.example.body"))
                            .font(exampleFont)
                        ProgressView(value: 0.25)
                        HStack {
                            Label("1/4", systemImage: "checkmark.circle.fill")
                            Spacer()
                            Text(AppStrings.localized("forecast.info.example.remaining"))
                                .font(exampleFont.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .accessibilityIdentifier("home.info.forecast")
            .navigationTitle(AppStrings.localized("forecast.info.title"))
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.done) {
                        dismiss()
                    }
                    .accessibilityIdentifier("home.info.done")
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var exampleFont: Font {
        .body
    }
}
