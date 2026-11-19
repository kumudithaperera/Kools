import AppKit
import KoolsCore
import SwiftUI

/// The menu bar item: the 😆 app icon when all is well, or, like a Live
/// Activity, a small colored pill showing only the icon of the most urgent
/// action.
@MainActor
enum MenuBarIcon {
    static let emoji = "😆"
    private static var cache: [StatusBadge?: NSImage] = [:]

    static func image(for badge: StatusBadge?) -> NSImage {
        if let cached = cache[badge] { return cached }
        let renderer = ImageRenderer(content: label(for: badge))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        // Colored, so it must not be tinted like a template image.
        image.isTemplate = false
        image.accessibilityDescription = badge?.summary ?? "Kools"
        cache[badge] = image
        return image
    }

    @ViewBuilder
    private static func label(for badge: StatusBadge?) -> some View {
        if let badge {
            Image(systemName: badge.symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 16)
                .background(badge.color.gradient, in: .capsule)
                .frame(width: 28, height: 18)
        } else {
            Text(emoji)
                .font(.system(size: 14))
                .frame(width: 20, height: 18)
        }
    }
}

extension StatusBadge {
    var color: Color {
        switch self {
        case .pull: .teal
        case .push: .blue
        case .commit: .orange
        case .warning: .red
        case .permission: .purple
        }
    }
}
