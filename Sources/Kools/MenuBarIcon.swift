import AppKit
import KoolsCore
import SwiftUI

/// The menu bar item: the 😆 app icon, with a small colored notification dot
/// when something needs you. The dot's color is the most urgent need.
@MainActor
enum MenuBarIcon {
    static let emoji = "😆"
    private static var cache: [StatusBadge?: NSImage] = [:]

    static func image(for needs: [StatusNeed]) -> NSImage {
        let badge = needs.first?.badge
        if let cached = cache[badge] { return cached }
        let renderer = ImageRenderer(content: label(for: badge))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        // The dot is colored, so it must not be tinted like a template image.
        image.isTemplate = false
        image.accessibilityDescription = needs.isEmpty
            ? "Kools"
            : needs.map(\.summary).joined(separator: ", ")
        cache[badge] = image
        return image
    }

    private static func label(for badge: StatusBadge?) -> some View {
        Text(emoji)
            .font(.system(size: 14))
            .frame(width: 20, height: 22)
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Circle()
                        .fill(badge.color)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                        .offset(x: 3, y: 1)
                }
            }
            // Room on the right for the dot (it overhangs by 3 pt), with a margin.
            .padding(.trailing, 5)
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
