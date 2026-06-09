import AppKit
import Foundation

@MainActor
struct WindowFocusService {
    func focusAppWindowOnScreenContainingMouse() {
        guard let targetScreen = NSScreen.screenContainingMouse else {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.mainWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let candidateWindow = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isMiniaturized })

        guard let window = candidateWindow else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let windowSize = window.frame.size
        let visibleFrame = targetScreen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - (windowSize.width / 2),
            y: visibleFrame.midY - (windowSize.height / 2)
        )

        let adjustedOrigin = CGPoint(
            x: max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - windowSize.width)),
            y: max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - windowSize.height))
        )

        window.setFrameOrigin(adjustedOrigin)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension NSScreen {
    static var screenContainingMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }
}
