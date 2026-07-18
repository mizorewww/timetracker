import Darwin
import Foundation

/// Foundation 27 can leave path aliases such as the system `/var` alias
/// unresolved. Resolve existing filesystem components with `realpath(3)`
/// before using `O_NOFOLLOW_ANY`, which otherwise rejects those aliases.
nonisolated enum CanonicalFileURL {
    fileprivate static func lexicallyNormalizedPathComponents(
        of url: URL
    ) -> [String]? {
        let decodedPath = url.path(percentEncoded: false)
        guard url.isFileURL,
              url.path.hasPrefix("/"),
              decodedPath.utf8.contains(0) == false else {
            return nil
        }
        var components = ["/"]
        for substring in url.path.split(
            separator: "/",
            omittingEmptySubsequences: true
        ) {
            let component = String(substring)
            switch component {
            case ".":
                continue
            case "..":
                guard components.count > 1 else { return nil }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        return components
    }

    fileprivate static func fileURL(
        pathComponents: [String],
        isDirectory: Bool
    ) -> URL {
        let path = "/" + pathComponents.dropFirst().joined(separator: "/")
        return URL(fileURLWithPath: path, isDirectory: isDirectory)
    }

    static func resolvingExistingPath(_ url: URL) throws -> URL {
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
              cursor.pathComponents.count > 1 {
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

nonisolated extension DurableLocalFile {
    func canonicalManagedPaths(
        at url: URL,
        through durableRootURL: URL
    ) throws -> (url: URL, root: URL) {
        guard let rootComponents = CanonicalFileURL
            .lexicallyNormalizedPathComponents(of: durableRootURL),
              let urlComponents = CanonicalFileURL
                .lexicallyNormalizedPathComponents(of: url) else {
            throw DurableLocalFileError.durableRootIsNotAncestor
        }
        guard urlComponents.starts(with: rootComponents) else {
            throw DurableLocalFileError.durableRootIsNotAncestor
        }

        let normalizedRoot = CanonicalFileURL.fileURL(
            pathComponents: rootComponents,
            isDirectory: true
        )
        let canonicalRoot = try canonicalDurableRoot(normalizedRoot)
        var canonicalURL = canonicalRoot
        for component in urlComponents.dropFirst(rootComponents.count) {
            canonicalURL.appendPathComponent(component)
        }
        return (canonicalURL, canonicalRoot)
    }
}
