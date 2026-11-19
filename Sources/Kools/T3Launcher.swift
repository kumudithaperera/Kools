import AppKit
import Foundation

/// Talks to the T3 Code desktop app through its `t3` CLI: opens projects, and
/// starts, messages and reads agent threads. T3 reuses the project whose
/// workspace root matches a folder, or creates one when opening it.
enum T3Launcher {
    static let bundleIdentifier = "com.t3tools.t3code"
    private static let cli = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".t3/bin/t3")

    struct LaunchError: Error, CustomStringConvertible {
        let description: String
    }

    /// Opens the folder in the app, bringing T3 Code to the front.
    static func open(_ folder: URL) async throws {
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            throw LaunchError(description: "T3 Code CLI not found at ~/.t3/bin/t3. Open T3 Code once to install it.")
        }
        do {
            try await run(["app", folder.path])
        } catch {
            // `t3 app` needs the desktop app running. Start it and retry once.
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { throw error }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            try await Task.sleep(for: .seconds(4))
            try await run(["app", folder.path])
        }
    }

    /// Starts an agent thread in the T3 project holding `project` and returns
    /// its id. With `inBackground`, T3 Code stays where it is unless the
    /// project doesn't exist yet; opening it is what creates it.
    @discardableResult
    static func startThread(in project: URL, title: String, message: String, inBackground: Bool = false) async throws -> String {
        if !inBackground { try await open(project) }
        // The message goes through stdin ("-"), so its length and quoting never matter.
        let arguments = ["thread", "start", "--json", "--title", title, project.path, "-"]
        let output: String
        do {
            output = try await run(arguments, input: message)
        } catch where inBackground {
            try await open(project)
            output = try await run(arguments, input: message)
        }
        guard let id = threadID(in: output) else {
            throw LaunchError(description: "T3 Code started a thread but didn't return its id")
        }
        return id
    }

    /// Sends the next message to a thread; a busy thread gets it as its next turn.
    static func send(to thread: String, message: String) async throws {
        try await run(["thread", "send", thread, "-"], input: message)
    }

    /// Waits for the thread's agent to finish its turn and returns its last
    /// reply. Pass `afterItemCount` (from `itemCount(of:)`, read before
    /// sending a follow-up) so the earlier answer isn't taken for the new one.
    static func waitForReply(in thread: String, afterItemCount: Int? = nil, timeout: Duration = .seconds(240)) async throws -> String {
        let busy: Set<String> = ["preparing", "queued", "starting", "running"]
        let deadline = ContinuousClock.now + timeout
        // A just-started thread can briefly report idle before its run begins.
        try await Task.sleep(for: .seconds(3))
        while ContinuousClock.now < deadline {
            let snapshot = try await show(thread)
            let isNew = afterItemCount.map { snapshot.itemCount > $0 } ?? true
            if isNew, !busy.contains(snapshot.status) {
                guard let reply = snapshot.lastReply else {
                    throw LaunchError(description: "The T3 thread ended without a reply (\(snapshot.status))")
                }
                return reply
            }
            try await Task.sleep(for: .seconds(2))
        }
        throw LaunchError(description: "T3 Code took too long to reply")
    }

    /// How many items the thread has; it grows with every turn.
    static func itemCount(of thread: String) async throws -> Int {
        try await show(thread).itemCount
    }

    private struct ThreadSnapshot {
        let status: String
        let itemCount: Int
        let lastReply: String?
    }

    private static func show(_ thread: String) async throws -> ThreadSnapshot {
        let output = try await run(["thread", "show", "--json", "--messages", "1", thread])
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["thread"] as? [String: Any],
              let status = info["status"] as? String
        else { throw LaunchError(description: "Couldn't read the T3 thread") }
        let messages = json["messages"] as? [[String: Any]] ?? []
        return ThreadSnapshot(
            status: status,
            itemCount: info["itemCount"] as? Int ?? 0,
            lastReply: messages.last(where: { $0["role"] as? String != "user" })?["text"] as? String
        )
    }

    /// `thread start --json` prints the new thread; its id is the first
    /// `threadId` (or `id`) found. Plain output is the bare id.
    static func threadID(in output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
            return findID(in: json)
        }
        return trimmed.isEmpty || trimmed.contains(where: \.isWhitespace) ? nil : trimmed
    }

    private static func findID(in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            for key in ["threadId", "id"] {
                if let id = dict[key] as? String { return id }
            }
            for nested in dict.values {
                if let id = findID(in: nested) { return id }
            }
        }
        return nil
    }

    /// Runs the CLI and returns its standard output.
    @discardableResult
    private static func run(_ arguments: [String], input: String? = nil) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = cli
            process.arguments = arguments
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            let stdin = Pipe()
            process.standardInput = input == nil ? FileHandle.nullDevice : stdin
            try process.run()
            if let input {
                stdin.fileHandleForWriting.write(Data(input.utf8))
                try stdin.fileHandleForWriting.close()
            }
            // Output can be large (a whole reply), so drain it first; error text is small.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw LaunchError(description: message.isEmpty ? "t3 \(arguments.prefix(2).joined(separator: " ")) exited with \(process.terminationStatus)" : message)
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}
