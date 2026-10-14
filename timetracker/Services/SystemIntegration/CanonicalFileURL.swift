import Darwin
import Foundation

/// Foundation 27 can leave path aliases such as the system `/var` alias
/// unresolved. Resolve existing filesystem components with `realpath(3)`
/// before using `O_NOFOLLOW_ANY`, which otherwise rejects those aliases.
nonisolated enum CanonicalFileURL {
    private static func resolvingExistingPath(_ url: URL) throws -> URL {
        let standardizedURL = url.standardizedFileURL
        let resolvedPath = standardizedURL.path.withCString {
            Darwin.realpath($0, nil)
        }
        guard let resolvedPath else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { free(resolvedPath) }
        // Keep the physical spelling returned by realpath. On iOS,
        // standardizedFileURL rewrites `/private/var` back to the `/var`
        // system alias that O_NOFOLLOW_ANY must reject.
        return URL(fileURLWithPath: String(cString: resolvedPath))
    }

    static func resolvingExistingAncestor(
        of url: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let standardizedURL = url.standardizedFileURL
        var cursor = standardizedURL
        var missingComponents: [String] = []

        while fileManager.fileExists(atPath: cursor.path) == false,
              cursor.pathComponents.count > 1
        {
            missingComponents.insert(cursor.lastPathComponent, at: 0)
            cursor.deleteLastPathComponent()
        }

        var canonicalURL = (try? resolvingExistingPath(cursor)) ?? cursor
        for component in missingComponents {
            canonicalURL.appendPathComponent(component)
        }
        return canonicalURL
    }
}
