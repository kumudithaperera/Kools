import AppKit
import Foundation

/// Opens a folder as a project in the T3 Code desktop app via its `t3 app` CLI.
/// T3 reuses the project whose workspace root matches the folder, or creates one.
enum T3Launcher {
    static let bundleIdentifier = "com.t3tools.t3code"
    private static let cli = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".t3/bin/t3")

    struct LaunchError: Error, CustomStringConvertible {
        let description: String
    }

    static func open(_ folder: URL) async throws {
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            throw LaunchError(description: "T3 Code CLI not found at ~/.t3/bin/t3. Open T3 Code once to install it.")
        }
        do {
            try await run(folder)
        } catch {
            // `t3 app` needs the desktop app running. Start it and retry once.
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { throw error }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            try await Task.sleep(for: .seconds(4))
            try await run(folder)
        }
    }

    private static func run(_ folder: URL) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = cli
            process.arguments = ["app", folder.path]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw LaunchError(description: message.isEmpty ? "t3 app exited with \(process.terminationStatus)" : message)
            }
        }.value
    }
}
