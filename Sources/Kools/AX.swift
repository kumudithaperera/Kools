import ApplicationServices
import AppKit

/// Small helpers over the Accessibility C API.
enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        guard let value = value(element, attribute), CFGetTypeID(value) == CFArrayGetTypeID() else { return nil }
        return (value as! [AnyObject]).map { $0 as! AXUIElement }
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// A frame in AppKit screen coordinates (origin bottom-left), from an
    /// element's position and size, which Accessibility gives from the top-left
    /// of the main display.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent),
              let mainHeight = NSScreen.screens.first?.frame.height
        else { return nil }
        return CGRect(x: origin.x, y: mainHeight - origin.y - extent.height, width: extent.width, height: extent.height)
    }

    static func application(_ pid: pid_t, timeout: Float = 0.25) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        // Keep a hung app from stalling Kools.
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }
}
