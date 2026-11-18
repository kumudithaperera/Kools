import AppKit
import RepoRadarCore
import SwiftUI

@main
struct RepoRadarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = RadarModel()

    var body: some Scene {
        MenuBarExtra {
            RadarMenu(model: model)
        } label: {
            Image(systemName: symbolName)
        }
        .menuBarExtraStyle(.menu)
    }

    private var symbolName: String {
        if model.lastScan == nil { return "arrow.triangle.2.circlepath" }
        switch model.worstSeverity {
        case .clean, .info: return "checkmark.circle"
        case .attention: return "arrow.triangle.branch"
        case .warning: return "exclamationmark.triangle"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, even when run as a bare binary.
        NSApp.setActivationPolicy(.accessory)
    }
}
