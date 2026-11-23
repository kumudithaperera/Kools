import AppKit

/// Quits Kools and opens it again.
enum Relauncher {
    /// Starts a detached shell that waits for this process to exit, then
    /// launches the app again, and quits. Runs the .app bundle when there is
    /// one, otherwise the bare executable (a `swift run` build).
    @MainActor
    static func restart() {
        let bundle = Bundle.main.bundleURL
        let launch = bundle.pathExtension == "app"
            ? ["/usr/bin/open", "-n", bundle.path]
            : [Bundle.main.executableURL?.path ?? CommandLine.arguments[0]]

        let script = "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; shift; exec \"$@\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier)] + launch
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return  // Couldn't schedule the relaunch; stay open rather than just quit.
        }
        NSApp.terminate(nil)
    }
}
