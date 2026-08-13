import AppKit
import UniformTypeIdentifiers

@MainActor
enum DocumentActions {
    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    static func createMarkdownDocument(suggestedName: String = "Untitled.md") -> Bool {
        let panel = NSSavePanel()
        panel.title = "Create a Markdown file"
        panel.prompt = "Create"
        panel.nameFieldLabel = "File name:"
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = defaultDirectory
        panel.allowedContentTypes = [.markdownDocument]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try Data().write(to: url, options: .atomic)
            open(url)
            return true
        } catch {
            presentError(
                title: "Couldn’t create the file",
                message: error.localizedDescription
            )
            return false
        }
    }

    static func chooseAndOpenDocument() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Open a Markdown file"
        panel.prompt = "Open"
        panel.directoryURL = defaultDirectory
        panel.allowedContentTypes = MarkViewDocument.readableContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        open(url)
        return true
    }

    static func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                Task { @MainActor in
                    presentError(title: "Couldn’t open the file", message: error.localizedDescription)
                }
            }
        }
    }

    static func recentDocuments(limit: Int = 10) -> [URL] {
        var seen = Set<URL>()
        return NSDocumentController.shared.recentDocumentURLs
            .filter { ["md", "markdown", "mmd"].contains($0.pathExtension.lowercased()) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .filter { seen.insert($0.standardizedFileURL).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private static func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
