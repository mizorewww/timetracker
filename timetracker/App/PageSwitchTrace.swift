import Foundation

// TEST-SCAFFOLD: Docs/ImplementationContexts/2026-08-06-page-switching-performance.md
// — remove when the page-switching performance work closes out.
//
// Emits millisecond-precision page-switch trace lines to stdout (visible in
// the xcodebuild log) so a scripted UI run can measure tab-switch latency
// without XCUITest's slow accessibility snapshot queries. Gate: --uitesting
// only; no effect in Release or normal Debug runs.
#if DEBUG
enum PageSwitchTrace {
    static var enabled: Bool {
        CommandLine.arguments.contains("--uitesting")
    }

    static func mark(_ event: String) {
        guard enabled else { return }
        let now = Date().timeIntervalSinceReferenceDate
        // stderr reaches the xcodebuild log (unlike stdout print or NSLog,
        // which XCUITest reroutes into the xcresult). Also append to the app
        // sandbox as a fallback for host-side reading via simctl.
        let line = String(format: "PERF-TRACE %.3f %@\n", now, event)
        FileHandle.standardError.write(line.data(using: .utf8)!)
        if let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            let url = documents.appendingPathComponent("perf-trace.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? line.data(using: .utf8)?.write(to: url)
            }
        }
    }
}
#endif
