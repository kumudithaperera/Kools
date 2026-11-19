/// Rules for quitting an app after its last window closes.
public enum QuitOnClose {
    /// Apps that are never quit, whatever the user picks: quitting Finder only
    /// relaunches it, and the others are system UI.
    public static let alwaysExempt: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.loginwindow",
    ]

    /// One window the window server lists for the app.
    public struct ServerWindow: Sendable {
        public var layer: Int
        public var width: Double
        public var height: Double
        public var alpha: Double

        public init(layer: Int, width: Double, height: Double, alpha: Double) {
            self.layer = layer
            self.width = width
            self.height = height
            self.alpha = alpha
        }

        /// A normal document-sized window. Layer 0 is the normal window layer;
        /// tiny or transparent ones are helper surfaces, not windows a person uses.
        var isUserWindow: Bool { layer == 0 && alpha > 0 && width >= 100 && height >= 100 }
    }

    /// Quit only when both sources agree there is nothing left. Accessibility
    /// can miss windows on other Spaces, so the window server gets a vote too,
    /// including off-screen windows. When the two disagree the app stays open:
    /// a missed quit is harmless, a wrong one is not.
    public static func shouldQuit(
        bundleID: String?,
        selected: Set<String>,
        accessibilityWindowCount: Int,
        serverWindows: [ServerWindow]
    ) -> Bool {
        guard let bundleID, selected.contains(bundleID), !alwaysExempt.contains(bundleID) else { return false }
        return accessibilityWindowCount == 0 && !serverWindows.contains(where: \.isUserWindow)
    }
}
