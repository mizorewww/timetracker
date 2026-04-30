import SwiftUI

struct ForecastExplanationCallout: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(.app("forecast.explainer.title"))
                    .font(.caption.weight(.semibold))
                Text(.app("forecast.explainer.body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.blue.opacity(0.12), lineWidth: 1)
        )
    }
}

struct ForecastInfoButton: View {
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(AppStrings.localized("forecast.info.title"))
        .popover(isPresented: $isPresented) {
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
                    InfoGuideRow(
                        icon: "checklist",
                        title: AppStrings.localized("forecast.info.requirements.title"),
                        bodyText: AppStrings.localized("forecast.info.requirements.body")
                    )
                    InfoGuideRow(
                        icon: "function",
                        title: AppStrings.localized("forecast.info.formula.title"),
                        bodyText: AppStrings.localized("forecast.info.formula.body")
                    )
                    InfoGuideRow(
                        icon: "folder.badge.gearshape",
                        title: AppStrings.localized("forecast.info.children.title"),
                        bodyText: AppStrings.localized("forecast.info.children.body")
                    )
                    InfoGuideRow(
                        icon: "archivebox",
                        title: AppStrings.localized("forecast.info.history.title"),
                        bodyText: AppStrings.localized("forecast.info.history.body")
                    )
                }

                Section(AppStrings.localized("forecast.info.example.title")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.localized("forecast.info.example.body"))
                            .font(.subheadline)
                        ProgressView(value: 0.25)
                        HStack {
                            Label("1/4", systemImage: "checkmark.circle.fill")
                            Spacer()
                            Text(AppStrings.localized("forecast.info.example.remaining"))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(AppStrings.localized("forecast.info.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.done) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct InfoGuideRow: View {
    let icon: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}
