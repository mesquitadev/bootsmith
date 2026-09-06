import SwiftUI

/// Rodando pelo Xcode ou por `swift run`, o executável do SwiftPM não tem bundle
/// nem Info.plist — sem isso o LaunchServices trata o processo como acessório e
/// a janela nunca vem para a frente.
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct BootsmithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @State private var model = AppModel()

    var body: some Scene {
        Window("Bootsmith", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 520, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L.t("About Bootsmith")) { openWindow(id: "about") }
            }
            CommandGroup(replacing: .newItem) {}
        }

        Window(L.t("About Bootsmith"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView().environment(model)
        }
    }
}
