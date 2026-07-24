import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = LimitsViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(model: model)
                .onAppear { model.start() }
        } label: {
            MenuBarLabel(model: model)
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
