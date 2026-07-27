import SwiftUI

#if os(macOS)
struct SettingsSidebarIconMetrics: Equatable {
    let symbolPointSize: CGFloat
    let slotDimension: CGFloat
    let spacing: CGFloat

    init(rowSize: SidebarRowSize) {
        switch rowSize {
        case .small:
            self.init(symbolPointSize: 12, slotDimension: 18, spacing: 6)
        case .medium:
            self.init(symbolPointSize: 14, slotDimension: 20, spacing: 8)
        case .large:
            self.init(symbolPointSize: 16, slotDimension: 24, spacing: 10)
        @unknown default:
            self.init(symbolPointSize: 14, slotDimension: 20, spacing: 8)
        }
    }

    init(symbolPointSize: CGFloat, slotDimension: CGFloat, spacing: CGFloat) {
        self.symbolPointSize = symbolPointSize
        self.slotDimension = slotDimension
        self.spacing = spacing
    }
}
#endif

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
    #if os(macOS)
    @Environment(\.sidebarRowSize) private var sidebarRowSize
    #endif

    var body: some View {
        #if os(macOS)
        macCategoryRow
        #else
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityCategoryRow
        } else {
            descriptiveCategoryRow
        }
        #endif
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

    #if os(macOS)
    private var macCategoryRow: some View {
        let metrics = SettingsSidebarIconMetrics(rowSize: sidebarRowSize)

        return HStack(spacing: metrics.spacing) {
            Image(systemName: category.systemImage)
                .font(.system(size: metrics.symbolPointSize, weight: .medium))
                .frame(width: metrics.slotDimension, height: metrics.slotDimension)
                .accessibilityHidden(true)

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
    #endif
}
