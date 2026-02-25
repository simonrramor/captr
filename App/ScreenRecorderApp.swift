import SwiftUI

@main
struct ScreenRecorderApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appDelegate.setupKeyboardShortcuts(appState: appState)
                    Task {
                        await appState.initialize()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 52)

        MenuBarExtra("Screen Recorder", systemImage: appState.captureEngine.state.isActive ? "record.circle.fill" : "record.circle") {
            MenuBarView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var keyboardShortcutManager: KeyboardShortcutManager?
    private var hasSetupShortcuts = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                window.styleMask = [.borderless, .fullSizeContentView]
                window.isMovableByWindowBackground = true
                window.backgroundColor = .clear
                window.hasShadow = true
                window.invalidateShadow()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @MainActor
    func setupKeyboardShortcuts(appState: AppState) {
        guard !hasSetupShortcuts else { return }
        hasSetupShortcuts = true
        keyboardShortcutManager = KeyboardShortcutManager(appState: appState)
        keyboardShortcutManager?.registerShortcuts()
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardShortcutManager?.unregisterShortcuts()
    }
}
