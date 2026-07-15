import SwiftUI

struct TaskCategorySectionHeader: View {
    let section: TaskTreeVisibleSectionModel
    var compact = false
    var showsBottomDivider = false
    var addTask: (() -> Void)?
    var editCategory: (() -> Void)?
    var deleteCategory: (() -> Void)?
#if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
#endif

    var body: some View {
        VStack(spacing: 5) {
            headerContent

            if showsBottomDivider {
                Divider()
            }
        }
        .accessibilityElement(
            children: addTask == nil && editCategory == nil && deleteCategory == nil ? .combine : .contain
        )
    }

    @ViewBuilder
    private var headerContent: some View {
        #if os(iOS)
        if dynamicTypeSize.isAccessibilitySize && !compact {
            accessibilityHeader
        } else {
            standardHeader
        }
        #else
        standardHeader
        #endif
    }

    private var standardHeader: some View {
        HStack(spacing: 8) {
            categorySymbol
            categoryTitle

            if !section.includesInForecast {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(AppStrings.localized("taskCategory.forecastDisabled"))
                    .accessibilityLabel(AppStrings.localized("taskCategory.forecastDisabled"))
            }

            Spacer(minLength: 8)
            categoryActionsMenu
        }
    }

    private var accessibilityHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                categorySymbol
                categoryTitle
            }

            HStack(alignment: .center, spacing: 8) {
                if !section.includesInForecast {
                    Label(
                        AppStrings.localized("taskCategory.forecastDisabled"),
                        systemImage: "chart.line.downtrend.xyaxis"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                categoryActionsMenu
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categorySymbol: some View {
        Image(systemName: section.iconName)
            .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
            .foregroundStyle(Color(hex: section.colorHex) ?? .secondary)
            .frame(minWidth: 18, alignment: .center)
            .accessibilityHidden(true)
    }

    private var categoryTitle: some View {
        Text(section.title)
            .font(compact ? .caption : .subheadline.weight(.semibold))
            .textCase(nil)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var categoryActionsMenu: some View {
        if !compact && (addTask != nil || editCategory != nil || deleteCategory != nil) {
            Menu {
                if let addTask {
                    Button(action: addTask) {
                        Label(AppStrings.localized("tasks.newRoot"), systemImage: "plus")
                    }
                }
                if let editCategory, section.categoryID != nil {
                    Button(action: editCategory) {
                        Label(AppStrings.localized("taskCategory.edit"), systemImage: "slider.horizontal.3")
                    }
                }
                if let deleteCategory, section.categoryID != nil {
                    Divider()
                    Button(role: .destructive, action: deleteCategory) {
                        Label(AppStrings.localized("taskCategory.delete"), systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: AppLayout.minimumInteractiveTarget, minHeight: AppLayout.minimumInteractiveTarget)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("tasks.category.actions.\(section.id)")
            .accessibilityLabel("\(section.title), \(AppStrings.localized("common.more"))")
        }
    }
}
