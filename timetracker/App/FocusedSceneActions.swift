import SwiftUI

#if os(macOS)
extension FocusedValues {
    @Entry var timeTrackerStore: TimeTrackerStore?
    @Entry var appPresentationRouter: AppPresentationRouter?
}
#endif
