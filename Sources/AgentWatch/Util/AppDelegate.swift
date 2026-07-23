import AppKit
import SwiftUI

/// Owns the status item; bridges AppKit (NSStatusItem, NSPopover) into SwiftUI.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    private var notchController: NotchController?
    private var mascotController: MascotOverlayController?
    private var approvalController: ApprovalPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("AppDelegate didFinishLaunching")

        // Background-only by default; switch to .regular when a window opens.
        NSApp.setActivationPolicy(.accessory)

        // Defensive: close any window auto-spawned or restored by SwiftUI before
        // defaultLaunchBehavior(.suppressed) could take effect. Must happen BEFORE
        // we create the StatusItemController — otherwise we'd close the NSPopover's
        // internal window and break the menu-bar interaction.
        for window in NSApp.windows where window.isVisible || window.isMiniaturized {
            window.close()
        }

        let sc = StatusItemController(state: AppState.shared)
        statusController = sc
        notchController = NotchController(state: AppState.shared, statusController: sc)
        mascotController = MascotOverlayController()
        approvalController = ApprovalPanelController()
    }

    /// Handle incoming `agentwatch://` URLs (clicked from Asana, Notes, etc.).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            TerminalLauncher.handleURL(url)
        }
    }

    /// Remove the approvals `.listening` marker promptly on quit so hook shims
    /// defer to the terminal immediately (the stale-marker check is only a backstop).
    func applicationWillTerminate(_ notification: Notification) {
        ApprovalBroker.shared.stop()
    }

    /// When the last window closes, drop back to accessory mode so the Dock icon disappears.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.setActivationPolicy(.accessory)
        }
        return true
    }
}
