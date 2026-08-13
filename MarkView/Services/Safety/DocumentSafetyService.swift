import Foundation
import CryptoKit

struct DocumentSafetyService {
    static func computeHash(text: String) -> String {
        let inputData = Data(text.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func hasFileChangedExternally(fileURL: URL?, originalHash: String) -> Bool {
        guard let url = fileURL else { return false }
        do {
            let currentText = try String(contentsOf: url, encoding: .utf8)
            let currentHash = computeHash(text: currentText)
            return currentHash != originalHash
        } catch {
            return false
        }
    }

    /// Writes a document straight to disk.
    ///
    /// - Warning: Not for a file owned by `DocumentGroup`. `NSDocument`
    ///   autosaves those itself and tracks their modification date; a write it
    ///   did not make looks to it like another application editing the file,
    ///   and it stops autosaving to ask "Save Anyway or Revert?". Mutating
    ///   `document.text` is all an open document needs. This exists for files
    ///   nothing else owns.
    static func saveDocumentSafely(to fileURL: URL?, content: String) throws {
        guard let url = fileURL else { return }
        let data = Data(content.utf8)
        try data.write(to: url, options: [.atomic])
    }

    static func validateMermaidSyntax(content: String) -> (isValid: Bool, error: String?) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "Empty Mermaid document") }

        let validDiagramHeaders = [
            "graph", "flowchart", "sequenceDiagram", "classDiagram",
            "stateDiagram", "erDiagram", "gantt", "pie", "gitGraph", "mindmap"
        ]

        let lines = trimmed.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let firstLine = lines.first(where: { !$0.isEmpty && !$0.hasPrefix("%%") }) else {
            return (false, "No valid Mermaid diagram type declared")
        }

        let hasValidHeader = validDiagramHeaders.contains { header in
            firstLine.hasPrefix(header)
        }

        if !hasValidHeader {
            return (false, "Unrecognized Mermaid diagram type: '\(firstLine)'")
        }

        return (true, nil)
    }
}
