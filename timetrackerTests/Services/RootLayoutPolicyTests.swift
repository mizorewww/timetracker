import SwiftUI
import Testing
@testable import timetracker

struct RootLayoutPolicyTests {
    @Test
    func widthBelowTheBreakpointUsesTheCompactShell() {
        #expect(RootLayoutPolicy.shell(forWidth: 719) == .compact)
        #expect(RootLayoutPolicy.shell(forWidth: 720) == .regular)
    }

    @Test
    func compactSizeClassWinsOverAWideMeasurement() {
        #expect(RootLayoutPolicy.shell(measured: .regular, horizontalSizeClass: .compact) == .compact)
        #expect(RootLayoutPolicy.shell(measured: .compact, horizontalSizeClass: .regular) == .compact)
        #expect(RootLayoutPolicy.shell(measured: nil, horizontalSizeClass: .regular) == .regular)
    }
}
