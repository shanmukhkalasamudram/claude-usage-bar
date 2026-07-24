import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = LimitsViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(model: model)
        } label: {
            // The label is instantiated as soon as the menu bar item appears at
            // launch (unlike the popover content, which is created only on first
            // click), so starting the refresh loop here means the percentage is
            // populated from launch — including login-item autostart.
            MenuBarLabel(model: model)
                .task { model.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Keeps the app out of the Dock and the app switcher — it lives only in the
/// menu bar. (Also enforced via `LSUIElement` in the bundled Info.plist.)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
