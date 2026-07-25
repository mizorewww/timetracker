import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case archivedTasks
    case focus
    case dataAndSync
    case intelligence
    case advanced

    var id: String {
        rawValue
    }

    var title: String {
        AppStrings.localized("settings.category.\(rawValue).title")
    }

    var subtitle: String {
        AppStrings.localized("settings.category.\(rawValue).subtitle")
    }

    var systemImage: String {
        switch self {
        case .general: "switch.2"
        case .archivedTasks: "archivebox"
        case .focus: "timer"
        case .dataAndSync: "externaldrive.badge.icloud"
        case .intelligence: "sparkles"
        case .advanced: "gearshape.2"
        }
    }

    var tint: Color {
        switch self {
        case .general: .blue
        case .archivedTasks: .orange
        case .focus: .orange
        case .dataAndSync: .cyan
        case .intelligence: .purple
        case .advanced: .gray
        }
    }
}

struct SettingsCategoryRow: View {
    let category: SettingsCategory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityCategoryRow
        } else {
            descriptiveCategoryRow
        }
    }

    private var accessibilityCategoryRow: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: category.systemImage, tint: category.tint)
            Text(category.title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(category.title))
        .accessibilityHint(Text(category.subtitle))
    }

    private var descriptiveCategoryRow: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsRowIcon(systemImage: category.systemImage, tint: category.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
