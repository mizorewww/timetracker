import SwiftUI

struct TaskSearchPlacementModifier: ViewModifier {
    @Binding var searchText: String
    let isCompactPhone: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        if isCompactPhone {
            content.searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: AppStrings.localized("tasks.searchPrompt")
            )
        } else {
            content.searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
        }
        #else
        content.searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
        #endif
    }
}
