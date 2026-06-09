import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return true
        }

        if let window = sender.windows.first(where: { !($0 is NSPanel) && !$0.styleMask.contains(.borderless) }) {
            sender.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        return true
    }
}
