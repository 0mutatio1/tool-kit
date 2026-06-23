import AppKit
import SwiftUI

@main
struct ToolKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 520)
                .onAppear {
                    viewModel.configureHotKeyIfNeeded()
                }
        }
        .defaultSize(width: 1280, height: 860)

        MenuBarExtra("ToolKit", systemImage: "diamond.fill") {
            Button("Open ToolKit") {
                openMainWindow()
            }

            Button("Clip Screen") {
                viewModel.runScreenClipCapture(preferredScreen: NSScreen.screenContainingMouse, keepWindowsHiddenAfterCapture: false)
            }

            Button("Show Copy History") {
                openWindow(id: "main")
                viewModel.openCopyHistory()
            }

            Button("Settings") {
                openWindow(id: "main")
                viewModel.openSettings()
            }

            Button(viewModel.settings.clipboardMonitoringEnabled ? "Pause Clipboard Monitoring" : "Resume Clipboard Monitoring") {
                viewModel.toggleClipboardMonitoring()
            }

            Divider()

            Button("Quit ToolKit") {
                viewModel.quitApp()
            }
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        viewModel.openMainWindow()
    }
}
