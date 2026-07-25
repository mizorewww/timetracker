import SwiftUI

struct TaskCategorySectionHeader: View {
    let section: TaskTreeVisibleSectionModel
    var compact = false
    var showsBottomDivider = false
    var addTask: (() -> Void)?
    var editCategory: (() -> Void)?
    var deleteCategory: (() -> Void)?
    var isExpanded: Bool?
    var toggleExpansion: (() -> Void)?
    var disclosureAccessibilityIdentifier: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            children: hasInteractiveControls ? .contain : .combine
        )
    }

    @ViewBuilder
    private var headerContent: some View {
        #if os(iOS)
        if dynamicTypeSize.isAccessibilitySize, !compact {
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
            categoryIdentity(showsForecastIndicator: true)
            categoryActionsMenu
        }
    }

    private var accessibilityHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                categoryIdentity(showsForecastIndicator: false)

                if section.includesInForecast {
                    categoryActionsMenu
                }
            }

            if !section.includesInForecast {
                HStack(alignment: .center, spacing: 8) {
                    Label(
                        AppStrings.localized("taskCategory.forecastDisabled"),
                        systemImage: "chart.line.downtrend.xyaxis"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)
                    categoryActionsMenu
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func categoryIdentity(
        showsForecastIndicator: Bool
    ) -> some View {
        if let isExpanded,
           let toggleExpansion,
           let disclosureAccessibilityIdentifier
        {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    toggleExpansion()
                }
            } label: {
                categoryIdentityLabel(
                    isExpanded: isExpanded,
                    showsForecastIndicator: showsForecastIndicator
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)
            .accessibilityValue(
                section.includesInForecast
                    ? ""
                    : AppStrings.localized("taskCategory.forecastDisabled")
            )
            .accessibilityHint(
                AppStrings.localized(
                    isExpanded ? "tasks.collapse" : "tasks.expand"
                )
            )
            .accessibilityIdentifier(disclosureAccessibilityIdentifier)
        } else {
            categoryIdentityLabel(
                isExpanded: nil,
                showsForecastIndicator: showsForecastIndicator
            )
        }
    }

    private func categoryIdentityLabel(
        isExpanded: Bool?,
        showsForecastIndicator: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if let isExpanded {
                Image(
                    systemName: isExpanded
                        ? "chevron.down"
                        : "chevron.forward"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 14, alignment: .center)
                .accessibilityHidden(true)
            }

            categorySymbol
            categoryTitle

            if showsForecastIndicator, !section.includesInForecast {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(AppStrings.localized("taskCategory.forecastDisabled"))
                    .accessibilityLabel(AppStrings.localized("taskCategory.forecastDisabled"))
            }

            Spacer(minLength: 8)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: isExpanded == nil
                ? nil
                : AppLayout.minimumInteractiveTarget,
            alignment: .leading
        )
        .contentShape(Rectangle())
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

    private var hasInteractiveControls: Bool {
        toggleExpansion != nil ||
            addTask != nil ||
            editCategory != nil ||
            deleteCategory != nil
    }

    @ViewBuilder
    private var categoryActionsMenu: some View {
        if !compact, addTask != nil || editCategory != nil || deleteCategory != nil {
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
                TrailingMenuLabel(systemImage: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("tasks.category.actions.\(section.id)")
            .accessibilityLabel("\(section.title), \(AppStrings.localized("common.more"))")
        }
    }
}
