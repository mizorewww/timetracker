import SwiftUI

struct TaskCategorySectionHeader: View {
    let section: TaskTreeVisibleSectionModel
    var compact = false
    var showsBottomDivider = false
    var addTask: (() -> Void)?
    var editCategory: (() -> Void)?

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: section.iconName)
                    .foregroundStyle(Color(hex: section.colorHex) ?? .secondary)
                    .frame(width: 18)

                Text(section.title)
                    .font(compact ? .caption : .subheadline.weight(.semibold))
                    .textCase(nil)

                if !section.includesInForecast {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(AppStrings.localized("taskCategory.forecastDisabled"))
                }

                Spacer(minLength: 8)

                if !compact && (addTask != nil || editCategory != nil) {
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
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if showsBottomDivider {
                Divider()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
