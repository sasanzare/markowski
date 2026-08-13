import AppKit
import Compression
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Text pulled out of an attached file, ready to put in front of a model.
struct ExtractedDocument: Identifiable, Equatable {
    enum Kind: String {
        case plainText
        case sourceCode
        case pdf
        case wordProcessing
        case spreadsheet

        var symbolName: String {
            switch self {
            case .plainText: return "doc.text"
            case .sourceCode: return "chevron.left.forwardslash.chevron.right"
            case .pdf: return "doc.richtext"
            case .wordProcessing: return "doc"
            case .spreadsheet: return "tablecells"
            }
        }

        var label: String {
            switch self {
            case .plainText: return "Text"
            case .sourceCode: return "Code"
            case .pdf: return "PDF"
            case .wordProcessing: return "Document"
            case .spreadsheet: return "Spreadsheet"
            }
        }
    }

    let id: UUID
    let fileName: String
    let kind: Kind
    /// What the model will actually be shown.
    let text: String
    /// Bytes on disk, for the chip's subtitle.
    let byteCount: Int
    /// A short, human description of the source: "12 pages", "3 sheets".
    let structureSummary: String?
    /// True when the file held more text than the limit allowed.
    let isTruncated: Bool

    init(
        id: UUID = UUID(),
        fileName: String,
        kind: Kind,
        text: String,
        byteCount: Int,
        structureSummary: String? = nil,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.text = text
        self.byteCount = byteCount
        self.structureSummary = structureSummary
        self.isTruncated = isTruncated
    }

    var byteCountDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// The subtitle under the file name in the composer.
    var summary: String {
        var parts: [String] = [kind.label]
        if let structureSummary { parts.append(structureSummary) }
        parts.append(byteCountDescription)
        if isTruncated { parts.append("shortened") }
        return parts.joined(separator: " · ")
    }

    /// How the file is handed to the model.
    ///
    /// Wrapped and labelled rather than pasted in raw, so the model can tell
    /// the difference between the user's question and the contents of a
    /// forty-page report, and can cite the file by name.
    var promptRepresentation: String {
        var header = "name=\"\(fileName)\" type=\"\(kind.label)\""
        if let structureSummary { header += " detail=\"\(structureSummary)\"" }
        if isTruncated { header += " note=\"shortened to fit\"" }
        return "<attached-file \(header)>\n\(text)\n</attached-file>"
    }
}

/// Turns a file the user attached into text.
///
/// Everything here leans on frameworks already in the system — PDFKit for PDFs,
/// AppKit's document readers for Word and RTF, and a small ZIP reader for
/// spreadsheets — so attaching a report never depends on the user having
/// anything installed.
enum DocumentTextExtractor {

    enum ExtractionError: LocalizedError, Equatable {
        case unsupported(String)
        case unreadable(String)
        case empty(String)
        case scannedPDF(String)
        case tooLarge(String)

        var errorDescription: String? {
            switch self {
            case .unsupported(let name):
                return "“\(name)” isn’t a file type I can read."
            case .unreadable(let name):
                return "“\(name)” couldn’t be opened."
            case .empty(let name):
                return "“\(name)” has no text in it."
            case .scannedPDF(let name):
                return "“\(name)” looks like a scan — it has pictures of text, not text, so there is nothing to read out of it."
            case .tooLarge(let name):
                return "“\(name)” is too big to attach."
            }
        }
    }

    /// Text past this point is dropped, with the chip saying so. Big enough for
    /// a long report, small enough not to bury the user's actual question.
    static let characterLimit = 120_000
    static let byteLimit = 40 * 1024 * 1024

    static let documentTextExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "mmd", "log", "csv", "tsv", "rst", "tex", "adoc"
    ]

    /// Extensions that are source code.
    ///
    /// Kept as a list only because the system does not have a registered type
    /// for every language — `.tsx`, `.svelte`, `.zig` and friends are unknown
    /// to it. Anything the system *does* recognise as text or source is
    /// accepted through `isTextLike` below, so a language missing from here is
    /// still attachable rather than silently refused.
    static let sourceCodeExtensions: Set<String> = [
        "swift", "py", "pyi", "rb", "js", "mjs", "cjs", "jsx", "ts", "tsx", "mts", "cts",
        "go", "rs", "java", "kt", "kts", "scala", "clj", "ex", "exs", "erl", "hs", "ml",
        "c", "h", "m", "mm", "cpp", "cc", "cxx", "hpp", "hh", "cs", "php", "pl", "lua",
        "r", "jl", "dart", "zig", "nim", "v", "sol", "sh", "bash", "zsh", "fish", "ps1",
        "sql", "graphql", "gql", "proto", "vue", "svelte", "astro",
        "json", "jsonc", "yaml", "yml", "toml", "ini", "cfg", "conf", "env", "properties",
        "xml", "html", "htm", "css", "scss", "sass", "less",
        "gradle", "cmake", "mk", "dockerfile", "gitignore", "editorconfig"
    ]

    static let pdfExtensions: Set<String> = ["pdf"]
    static let wordExtensions: Set<String> = ["docx", "doc", "rtf", "rtfd", "odt", "pages"]
    static let spreadsheetExtensions: Set<String> = ["xlsx", "xlsm"]

    static var supportedTypes: [UTType] {
        let extensions = documentTextExtensions
            .union(sourceCodeExtensions)
            .union(pdfExtensions)
            .union(wordExtensions)
            .union(spreadsheetExtensions)
        var types = extensions.compactMap { UTType(filenameExtension: $0) }
        types.append(contentsOf: [
            .plainText, .text, .sourceCode, .script, .shellScript,
            .pdf, .rtf, .commaSeparatedText, .json, .xml, .yaml, .html
        ])
        // Duplicates make the open panel's type filter behave oddly.
        var seen = Set<String>()
        return types.filter { seen.insert($0.identifier).inserted }
    }

    /// Whether the system already understands this file to be text of some
    /// kind. This is what keeps the lists above from having to name every
    /// language that exists.
    static func isTextLike(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return [UTType.text, .plainText, .sourceCode, .script, .shellScript, .json, .xml, .yaml, .html, .delimitedText]
            .contains { type.conforms(to: $0) }
    }

    static func isSupported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        // A file with no extension but a well-known name is still text.
        if ext.isEmpty {
            return ["dockerfile", "makefile", "rakefile", "gemfile", "procfile", "license", "readme"]
                .contains(url.lastPathComponent.lowercased())
        }
        return documentTextExtensions.contains(ext)
            || sourceCodeExtensions.contains(ext)
            || pdfExtensions.contains(ext)
            || wordExtensions.contains(ext)
            || spreadsheetExtensions.contains(ext)
            || isTextLike(url: url)
    }

    /// Reads a file into text. Off the main thread: a long PDF takes real time,
    /// and the composer stays responsive while it happens.
    static func extract(from url: URL) async throws -> ExtractedDocument {
        let name = url.lastPathComponent
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard byteCount <= byteLimit else { throw ExtractionError.tooLarge(name) }

        let ext = url.pathExtension.lowercased()
        let localURL = url

        return try await Task.detached(priority: .userInitiated) { () -> ExtractedDocument in
            let raw: String
            let kind: ExtractedDocument.Kind
            var structure: String?

            if pdfExtensions.contains(ext) {
                kind = .pdf
                let extracted = try pdfText(at: localURL, name: name)
                raw = extracted.text
                structure = extracted.pageCount == 1 ? "1 page" : "\(extracted.pageCount) pages"
            } else if spreadsheetExtensions.contains(ext) {
                kind = .spreadsheet
                let extracted = try spreadsheetText(at: localURL, name: name)
                raw = extracted.text
                structure = extracted.sheetCount == 1 ? "1 sheet" : "\(extracted.sheetCount) sheets"
            } else if wordExtensions.contains(ext) {
                kind = .wordProcessing
                raw = try wordProcessingText(at: localURL, name: name)
            } else if documentTextExtensions.contains(ext)
                        || sourceCodeExtensions.contains(ext)
                        || isSupported(url: localURL) {
                if ["csv", "tsv"].contains(ext) {
                    kind = .spreadsheet
                } else if sourceCodeExtensions.contains(ext) {
                    kind = .sourceCode
                    structure = ext
                } else {
                    kind = .plainText
                }
                raw = try plainText(at: localURL, name: name)
            } else {
                throw ExtractionError.unsupported(name)
            }

            let cleaned = tidy(raw)
            guard !cleaned.isEmpty else { throw ExtractionError.empty(name) }

            let truncated = cleaned.count > characterLimit
            return ExtractedDocument(
                fileName: name,
                kind: kind,
                text: truncated ? String(cleaned.prefix(characterLimit)) : cleaned,
                byteCount: byteCount,
                structureSummary: structure,
                isTruncated: truncated
            )
        }.value
    }

    // MARK: - Per-format readers

    /// Reads text with an encoding fallback.
    ///
    /// Assuming UTF-8 and giving up otherwise meant a file saved by Excel or an
    /// older Windows editor attached as nothing at all, with no explanation.
    static func plainText(at url: URL, name: String) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) { return utf8 }

        var probed: NSString?
        if let data = try? Data(contentsOf: url) {
            let encoding = NSString.stringEncoding(
                for: data,
                encodingOptions: [.suggestedEncodingsKey: [
                    NSNumber(value: String.Encoding.utf8.rawValue),
                    NSNumber(value: String.Encoding.utf16.rawValue),
                    NSNumber(value: String.Encoding.isoLatin1.rawValue),
                    NSNumber(value: String.Encoding.windowsCP1252.rawValue)
                ]],
                convertedString: &probed,
                usedLossyConversion: nil
            )
            if encoding != 0, let probed { return probed as String }
        }
        throw ExtractionError.unreadable(name)
    }

    static func pdfText(at url: URL, name: String) throws -> (text: String, pageCount: Int) {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.unreadable(name)
        }

        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // Page markers give the model something to cite.
            pages.append("[page \(index + 1)]\n\(text)")
        }

        guard !pages.isEmpty else {
            // A PDF with pages but no extractable text is a scan, and saying so
            // is far more use than handing back an empty attachment.
            throw document.pageCount > 0
                ? ExtractionError.scannedPDF(name)
                : ExtractionError.empty(name)
        }
        return (pages.joined(separator: "\n\n"), document.pageCount)
    }

    /// Word, RTF, and OpenDocument, via the readers AppKit already ships.
    static func wordProcessingText(at url: URL, name: String) throws -> String {
        let ext = url.pathExtension.lowercased()
        var candidates: [NSAttributedString.DocumentType] = []
        switch ext {
        case "docx": candidates = [.officeOpenXML]
        case "doc": candidates = [.docFormat]
        case "rtf": candidates = [.rtf]
        case "rtfd": candidates = [.rtfd]
        case "odt": candidates = [.openDocument]
        default: candidates = [.officeOpenXML, .rtf]
        }
        // `.pages` and anything unexpected still get a try — some export as
        // one of the formats above.
        candidates.append(contentsOf: [.officeOpenXML, .rtf, .plain])

        for type in candidates {
            if let attributed = try? NSAttributedString(
                url: url,
                options: [.documentType: type],
                documentAttributes: nil
            ) {
                let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            }
        }
        throw ExtractionError.unreadable(name)
    }

    // MARK: - Spreadsheets

    static func spreadsheetText(at url: URL, name: String) throws -> (text: String, sheetCount: Int) {
        guard let data = try? Data(contentsOf: url),
              let archive = ZIPArchive(data: data) else {
            throw ExtractionError.unreadable(name)
        }

        // Shared strings are stored once and referenced by index, so cells
        // holding text are meaningless without them.
        var sharedStrings: [String] = []
        if let stringsData = archive.contents(of: "xl/sharedStrings.xml"),
           let xml = String(data: stringsData, encoding: .utf8) {
            sharedStrings = parseSharedStrings(xml)
        }

        let sheetPaths = archive.entryNames
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted()
        guard !sheetPaths.isEmpty else { throw ExtractionError.unreadable(name) }

        var sheets: [String] = []
        for (index, path) in sheetPaths.enumerated() {
            guard let sheetData = archive.contents(of: path),
                  let xml = String(data: sheetData, encoding: .utf8) else { continue }
            let rows = parseSheet(xml, sharedStrings: sharedStrings)
            guard !rows.isEmpty else { continue }

            // Written as a Markdown-ish grid, which models read well and which
            // matches how the rest of this app talks about tables.
            let body = rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
            sheets.append("[sheet \(index + 1)]\n\(body)")
        }

        guard !sheets.isEmpty else { throw ExtractionError.empty(name) }
        return (sheets.joined(separator: "\n\n"), sheetPaths.count)
    }

    static func parseSharedStrings(_ xml: String) -> [String] {
        // Each <si> is one string, possibly split across several <t> runs.
        matches(of: "<si>(.*?)</si>", in: xml).map { item in
            matches(of: "<t[^>]*>(.*?)</t>", in: item)
                .map(decodeXMLEntities)
                .joined()
        }
    }

    static func parseSheet(_ xml: String, sharedStrings: [String]) -> [[String]] {
        matches(of: "<row[^>]*>(.*?)</row>", in: xml).compactMap { rowXML in
            let cells = matches(of: "<c([^>]*)>(.*?)</c>", in: rowXML, groups: 2).map { groups -> String in
                let attributes = groups[0]
                let body = groups[1]

                if attributes.contains("t=\"s\"") {
                    // A shared-string reference.
                    guard let raw = matches(of: "<v>(.*?)</v>", in: body).first,
                          let index = Int(raw), sharedStrings.indices.contains(index) else {
                        return ""
                    }
                    return sharedStrings[index]
                }
                if attributes.contains("t=\"inlineStr\"") {
                    return matches(of: "<t[^>]*>(.*?)</t>", in: body).map(decodeXMLEntities).joined()
                }
                return matches(of: "<v>(.*?)</v>", in: body).first.map(decodeXMLEntities) ?? ""
            }
            // A row of nothing but empty cells is spacing, not data.
            return cells.contains(where: { !$0.isEmpty }) ? cells : nil
        }
    }

    // MARK: - Helpers

    /// Collapses the runs of blank lines these formats tend to produce, so the
    /// model isn't paying for whitespace.
    static func tidy(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(
                of: "\n{3,}",
                with: "\n\n",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeXMLEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"),
            ("&#10;", "\n"), ("&#9;", "\t"), ("&amp;", "&")
        ] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    private static func matches(of pattern: String, in text: String) -> [String] {
        matches(of: pattern, in: text, groups: 1).map { $0[0] }
    }

    private static func matches(of pattern: String, in text: String, groups: Int) -> [[String]] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let source = text as NSString
        return expression
            .matches(in: text, options: [], range: NSRange(location: 0, length: source.length))
            .map { match in
                (1...groups).map { index in
                    let range = match.range(at: index)
                    return range.location == NSNotFound ? "" : source.substring(with: range)
                }
            }
    }
}

/// Just enough ZIP to read a spreadsheet.
///
/// An `.xlsx` is a ZIP of XML, and nothing in the system frameworks will open
/// one — so rather than take on a dependency for a single file format, this
/// reads the central directory and inflates the two entries that matter.
/// Deliberately read-only and minimal.
struct ZIPArchive {
    private struct Entry {
        let name: String
        let isCompressed: Bool
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private let entries: [String: Entry]

    var entryNames: [String] { Array(entries.keys) }

    init?(data: Data) {
        self.data = data
        guard let directoryStart = Self.centralDirectoryOffset(in: data) else { return nil }

        var parsed: [String: Entry] = [:]
        var cursor = directoryStart
        while cursor + 46 <= data.count, Self.readUInt32(data, at: cursor) == 0x0201_4b50 {
            let method = Self.readUInt16(data, at: cursor + 10)
            let compressedSize = Int(Self.readUInt32(data, at: cursor + 20))
            let uncompressedSize = Int(Self.readUInt32(data, at: cursor + 24))
            let nameLength = Int(Self.readUInt16(data, at: cursor + 28))
            let extraLength = Int(Self.readUInt16(data, at: cursor + 30))
            let commentLength = Int(Self.readUInt16(data, at: cursor + 32))
            let localOffset = Int(Self.readUInt32(data, at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { break }
            let name = String(
                data: data.subdata(in: nameStart..<(nameStart + nameLength)),
                encoding: .utf8
            ) ?? ""

            if !name.isEmpty {
                parsed[name] = Entry(
                    name: name,
                    isCompressed: method == 8,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset
                )
            }
            cursor = nameStart + nameLength + extraLength + commentLength
        }

        guard !parsed.isEmpty else { return nil }
        self.entries = parsed
    }

    func contents(of name: String) -> Data? {
        guard let entry = entries[name] else { return nil }

        // The local header repeats the name and extra fields, and its lengths
        // are the ones that count — the central directory's may differ.
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, Self.readUInt32(data, at: header) == 0x0403_4b50 else {
            return nil
        }
        let nameLength = Int(Self.readUInt16(data, at: header + 26))
        let extraLength = Int(Self.readUInt16(data, at: header + 28))
        let start = header + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start <= end, end <= data.count else { return nil }

        let payload = data.subdata(in: start..<end)
        guard entry.isCompressed else { return payload }
        return Self.inflate(payload, expectedSize: entry.uncompressedSize)
    }

    /// Raw DEFLATE, which is what ZIP stores and what `COMPRESSION_ZLIB` means
    /// in Apple's compression framework.
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty else { return Data() }
        let capacity = max(expectedSize, data.count * 8) + 4096
        var output = Data(count: capacity)

        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, capacity,
                    sourceBase, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    /// The end-of-central-directory record sits at the very end, after a
    /// comment of unknown length, so it is found by scanning backwards.
    private static func centralDirectoryOffset(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let earliest = max(0, data.count - 22 - 65_535)
        var cursor = data.count - 22
        while cursor >= earliest {
            if readUInt32(data, at: cursor) == 0x0605_4b50 {
                return Int(readUInt32(data, at: cursor + 16))
            }
            cursor -= 1
        }
        return nil
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
