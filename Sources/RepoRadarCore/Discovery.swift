import Foundation

public struct DiscoveredRepo: Hashable, Sendable {
    public let path: URL
    public let kind: RepoKind
}

public enum Discovery {
    /// Directories that are never worth descending into: dependency and build output.
    static let skippedNames: Set<String> = [
        "node_modules", "Pods", "Carthage", "DerivedData", "build", "dist", "vendor",
    ]

    /// Finds git working trees under `root`, including repos nested inside other repos.
    /// Skips hidden directories, symlinks, packages (`.app`, `.xcodeproj`) and `skippedNames`.
    public static func findRepos(under root: URL, maxDepth: Int) -> [DiscoveredRepo] {
        var results: [DiscoveredRepo] = []
        walk(root.standardizedFileURL, depth: 0, maxDepth: maxDepth, into: &results)
        return results
    }

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]

    private static func walk(_ dir: URL, depth: Int, maxDepth: Int, into results: inout [DiscoveredRepo]) {
        if let kind = kind(ofGitEntry: dir.appendingPathComponent(".git")) {
            results.append(DiscoveredRepo(path: dir, kind: kind))
        }
        guard depth < maxDepth else { return }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return }

        for child in children.sorted(by: { $0.path < $1.path }) {
            guard !skippedNames.contains(child.lastPathComponent),
                  let values = try? child.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  values.isPackage != true
            else { continue }
            walk(child, depth: depth + 1, maxDepth: maxDepth, into: &results)
        }
    }

    static func kind(ofGitEntry gitURL: URL) -> RepoKind? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return .repository }
        // A `.git` file: "gitdir: <path>"
        guard let pointer = try? String(contentsOf: gitURL, encoding: .utf8) else { return .repository }
        if pointer.contains("/worktrees/") { return .worktree }
        if pointer.contains("/modules/") { return .submodule }
        return .repository
    }

    /// The closest repo in `candidates` that strictly contains `path`.
    public static func nearestAncestor(of path: URL, in candidates: [URL]) -> URL? {
        let components = path.standardizedFileURL.pathComponents
        return candidates
            .filter { candidate in
                let ancestor = candidate.standardizedFileURL.pathComponents
                return ancestor.count < components.count && Array(components.prefix(ancestor.count)) == ancestor
            }
            .max { $0.pathComponents.count < $1.pathComponents.count }
    }
}
