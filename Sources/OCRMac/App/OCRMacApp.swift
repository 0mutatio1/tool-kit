import SwiftUI

@main
struct OCRMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
                .frame(minWidth: 720, minHeight: 520)
                .onAppear {
                    viewModel.configureHotKeyIfNeeded()
                }
        }
        .defaultSize(width: 820, height: 620)
    }
}
