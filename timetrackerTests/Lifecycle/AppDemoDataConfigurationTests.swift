import Testing
@testable import timetracker

struct AppDemoDataConfigurationTests {
    @Test
    func launchArgumentSelectsTheDemoMode() {
        let key = "-\(AppDemoDataConfiguration.overrideKey)"
        #expect(AppDemoDataConfiguration.commandLineMode(arguments: ["app", key, "replaceOnLaunch"]) == .replaceOnLaunch)
        #expect(AppDemoDataConfiguration.commandLineMode(arguments: ["app", "\(key)=seedIfEmpty"]) == .seedIfEmpty)
        #expect(AppDemoDataConfiguration.commandLineMode(arguments: ["app"]) == nil)
        #expect(AppDemoDataConfiguration.commandLineMode(arguments: ["app", key, "unknown"]) == nil)
    }
}
