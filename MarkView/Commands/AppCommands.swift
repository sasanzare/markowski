import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        SidebarCommands()
        
        CommandGroup(replacing: .newItem) {
            Button("New Markdown File") {
                DocumentActions.createMarkdownDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Divider()

            Button("Open…") {
                DocumentActions.chooseAndOpenDocument()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
    }
}
