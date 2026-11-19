import AppKit
import SwiftUI

@main
struct KoolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            KoolsPanel(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: model.statusBadge))
        }
        .menuBarExtraStyle(.window)

        Window("Kools Settings", id: KoolsApp.mainWindowID) {
            MainWindow(model: model)
        }
        .windowResizability(.contentSize)
    }

    static let mainWindowID = "main"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, even when run as a bare binary.
        NSApp.setActivationPolicy(.accessory)
    }
}
