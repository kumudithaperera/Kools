import Darwin
import Foundation

public struct ICloudDetector: Sendable {
    /// Paths treated as iCloud-synced regardless of what macOS reports.
    public var syncedRoots: [URL]

    public init(syncedRoots: [URL]) {
        self.syncedRoots = syncedRoots
    }

    public static func system(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ICloudDetector {
        ICloudDetector(syncedRoots: [home.appendingPathComponent("Library/Mobile Documents")])
    }

    public func isInICloud(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        for root in syncedRoots {
            let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
            if path == rootPath || path.hasPrefix(rootPath + "/") { return true }
        }
        // Covers Desktop & Documents sync, which keeps the ~/Desktop path.
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
        return values?.isUbiquitousItem == true
    }
}

public enum EvictionCheck {
    /// `SF_DATALESS` from <sys/stat.h>: the file's contents are not on disk.
    static let datalessFlag: UInt32 = 0x4000_0000

    /// Counts tracked files and `.git` internals whose contents iCloud has evicted.
    /// Uses lstat only, so checking never triggers a download. Stops at `limit`.
    public static func evictedCount(in repo: URL, runner: GitRunner, limit: Int = 50) -> Int {
        var count = 0
        func check(_ path: String) -> Bool {
            if isEvicted(path) { count += 1 }
            return count >= limit
        }

        let gitDir = repo.appendingPathComponent(".git")
        if let enumerator = FileManager.default.enumerator(atPath: gitDir.path) {
            var seen = 0
            while let relative = enumerator.nextObject() as? String, seen < 5000 {
                seen += 1
                if check(gitDir.appendingPathComponent(relative).path) { return count }
            }
        }

        if let listing = try? runner.run(.trackedFiles, in: repo) {
            for relative in listing.split(separator: "\0") {
                if check(repo.appendingPathComponent(String(relative)).path) { return count }
            }
        }
        return count
    }

    static func isEvicted(_ path: String) -> Bool {
        var info = stat()
        if lstat(path, &info) == 0 {
            return info.st_flags & datalessFlag != 0
        }
        // Older iCloud replaced evicted files with a hidden ".name.icloud" placeholder.
        let url = URL(fileURLWithPath: path)
        let placeholder = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud").path
        return FileManager.default.fileExists(atPath: placeholder)
    }
}
