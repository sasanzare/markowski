import Foundation

struct DocumentMetadata {
    let fileName: String
    let fileExtension: String
    let fileSizeFormatted: String
    let rawByteCount: Int64
    let modificationDate: Date?
    let modificationDateFormatted: String
    let lineCount: Int
    let wordCount: Int
    let characterCount: Int
    let path: String
}

enum DocumentLoader {
    static func loadString(from url: URL) throws -> String {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func getMetadata(for url: URL?, text: String) -> DocumentMetadata {
        let fileName = url?.lastPathComponent ?? "Untitled"
        let fileExtension = url?.pathExtension.lowercased() ?? "md"
        let path = url?.path ?? ""

        var fileSize: Int64 = 0
        var modDate: Date? = nil

        if let url = url {
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                modDate = attrs[.modificationDate] as? Date
            }
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        } else {
            fileSize = Int64(text.utf8.count)
        }

        let lines = text.components(separatedBy: .newlines).count
        let characters = text.count
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count

        let sizeFormatted = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        
        let dateFormatted: String
        if let modDate = modDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            dateFormatted = formatter.string(from: modDate)
        } else {
            dateFormatted = "Unknown"
        }

        return DocumentMetadata(
            fileName: fileName,
            fileExtension: fileExtension,
            fileSizeFormatted: sizeFormatted,
            rawByteCount: fileSize,
            modificationDate: modDate,
            modificationDateFormatted: dateFormatted,
            lineCount: lines,
            wordCount: words,
            characterCount: characters,
            path: path
        )
    }
}
