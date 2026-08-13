import AppKit
import SwiftUI

final class MarkowskiAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct MarkViewApp: App {
    @NSApplicationDelegateAdaptor(MarkowskiAppDelegate.self) private var appDelegate

    init() {
        MarkowskiTypography.registerFontsIfNeeded()
    }

    var body: some Scene {
        Window("Welcome to Markowski", id: "welcome") {
            WelcomeView()
        }
        .defaultSize(width: 820, height: 540)
        .windowResizability(.contentMinSize)

        DocumentGroup(newDocument: MarkViewDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            AppCommands()
        }

        Settings {
            AISettingsView()
        }
    }
}
