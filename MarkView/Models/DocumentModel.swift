import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var markdownDocument: UTType {
        UTType(importedAs: "public.markdown", conformingTo: .text)
    }

    static var mermaidDiagram: UTType {
        UTType(exportedAs: "org.mermaid.diagram", conformingTo: .text)
    }
}

struct MarkViewDocument: FileDocument {
    var text: String
    var fileURL: URL?

    static var readableContentTypes: [UTType] {
        [.markdownDocument, .plainText, .mermaidDiagram]
    }

    init(text: String = "", fileURL: URL? = nil) {
        self.text = text
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            if let data = configuration.file.regularFileContents,
               let string = String(data: data, encoding: .ascii) {
                self.text = string
                self.fileURL = nil
                return
            }
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = string
        self.fileURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return .init(regularFileWithContents: data)
    }
}
