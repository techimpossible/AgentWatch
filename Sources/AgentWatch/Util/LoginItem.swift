import Foundation
import ServiceManagement

/// Wraps SMAppService.mainApp so the popover can show / toggle "Launch at login".
@MainActor
enum LoginItem {
    /// True if AgentWatch is registered to launch on login right now.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggle the login-item state. Returns the new state on success, nil on failure.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled
        } catch {
            DebugLog.write("loginItem: \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
            return nil
        }
    }
}
