import AppKit
import Foundation

@MainActor
struct AppWindowVisibilityService {
    struct HiddenWindowState {
        let window: NSWindow
        let wasKeyWindow: Bool
        let frame: CGRect
    }

    func hideRegularWindows() -> [HiddenWindowState] {
        NSApp.windows
            .filter { window in
                window.isVisible &&
                !(window is NSPanel) &&
                !window.styleMask.contains(.borderless)
            }
            .map { window in
                let state = HiddenWindowState(window: window, wasKeyWindow: window.isKeyWindow, frame: window.frame)
                window.orderOut(nil)
                return state
            }
    }

    func restoreWindows(_ states: [HiddenWindowState]) {
        for state in states {
            state.window.setFrame(state.frame, display: false)
            state.window.orderFront(nil)
            if state.wasKeyWindow {
                state.window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
