import SwiftUI
import Testing
@testable import timetracker

#if os(macOS)
struct SettingsCategoryUIContractTests {
    @Test
    func categoryIconMetricsFollowTheSystemSidebarSize() {
        let small = SettingsSidebarIconMetrics(rowSize: .small)
        let medium = SettingsSidebarIconMetrics(rowSize: .medium)
        let large = SettingsSidebarIconMetrics(rowSize: .large)

        #expect(small == .init(symbolPointSize: 12, slotDimension: 18, spacing: 6))
        #expect(medium == .init(symbolPointSize: 14, slotDimension: 20, spacing: 8))
        #expect(large == .init(symbolPointSize: 16, slotDimension: 24, spacing: 10))
    }
}
#endif
