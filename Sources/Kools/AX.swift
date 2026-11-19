import ApplicationServices

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

    static func application(_ pid: pid_t, timeout: Float = 0.25) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        // Keep a hung app from stalling Kools.
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }
}
