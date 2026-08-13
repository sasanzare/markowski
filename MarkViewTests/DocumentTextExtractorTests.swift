import XCTest
import AppKit
import PDFKit
@testable import MarkView

/// Attaching a file is only useful if the text that comes out is the text that
/// was in it. These build real files on disk and read them back, because the
/// failure mode being guarded against — a file that attaches as silently empty
/// — looks exactly like success from the outside.
final class DocumentTextExtractorTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("markowski-extract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ contents: String, to name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Plain text

    func testPlainTextIsReadWithItsContent() async throws {
        let url = try write("# Title\n\nSome body text.", to: "notes.md")
        let extracted = try await DocumentTextExtractor.extract(from: url)

        XCTAssertEqual(extracted.kind, .plainText)
        XCTAssertEqual(extracted.fileName, "notes.md")
        XCTAssertTrue(extracted.text.contains("Some body text."))
        XCTAssertFalse(extracted.isTruncated)
    }

    /// Not every file is UTF-8. Assuming it was meant a file saved by an older
    /// Windows editor attached as nothing at all.
    func testNonUTF8TextIsStillRead() throws {
        let url = directory.appendingPathComponent("latin.txt")
        let data = try XCTUnwrap("Café résumé — naïve".data(using: .windowsCP1252))
        try data.write(to: url)

        let text = try DocumentTextExtractor.plainText(at: url, name: "latin.txt")
        XCTAssertTrue(text.contains("Caf"), "Got: \(text)")
        XCTAssertFalse(text.isEmpty)
    }

    func testCSVCountsAsASpreadsheet() async throws {
        let url = try write("name,qty\nwidget,4", to: "stock.csv")
        let extracted = try await DocumentTextExtractor.extract(from: url)

        XCTAssertEqual(extracted.kind, .spreadsheet)
        XCTAssertTrue(extracted.text.contains("widget,4"))
    }

    func testAnEmptyFileIsRefusedRatherThanAttachedBlank() async throws {
        let url = try write("   \n\n  ", to: "blank.txt")
        do {
            _ = try await DocumentTextExtractor.extract(from: url)
            XCTFail("An empty file should not attach as an empty attachment")
        } catch let error as DocumentTextExtractor.ExtractionError {
            XCTAssertEqual(error, .empty("blank.txt"))
        }
    }

    func testUnsupportedTypeIsRefused() async throws {
        let url = directory.appendingPathComponent("thing.bin")
        try Data([0x00, 0x01, 0x02]).write(to: url)

        do {
            _ = try await DocumentTextExtractor.extract(from: url)
            XCTFail("A binary file has no text to read")
        } catch let error as DocumentTextExtractor.ExtractionError {
            XCTAssertEqual(error, .unsupported("thing.bin"))
        }
    }

    // MARK: - PDF

    private func makePDF(pages: [String], to name: String) throws -> URL {
        let document = PDFDocument()
        for (index, text) in pages.enumerated() {
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: 612, height: 792)
            let consumer = try XCTUnwrap(CGDataConsumer(data: data))
            let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))

            context.beginPDFPage(nil)
            let attributed = NSAttributedString(
                string: text,
                attributes: [.font: NSFont.systemFont(ofSize: 24)]
            )
            let line = CTLineCreateWithAttributedString(attributed)
            context.textPosition = CGPoint(x: 60, y: 700)
            CTLineDraw(line, context)
            context.endPDFPage()
            context.closePDF()

            let page = try XCTUnwrap(PDFDocument(data: data as Data)?.page(at: 0))
            document.insert(page, at: index)
        }

        let url = directory.appendingPathComponent(name)
        XCTAssertTrue(document.write(to: url))
        return url
    }

    func testPDFTextIsExtractedWithPageMarkers() async throws {
        let url = try makePDF(pages: ["First page body", "Second page body"], to: "report.pdf")
        let extracted = try await DocumentTextExtractor.extract(from: url)

        XCTAssertEqual(extracted.kind, .pdf)
        XCTAssertEqual(extracted.structureSummary, "2 pages")
        XCTAssertTrue(extracted.text.contains("First page body"), "Got: \(extracted.text)")
        XCTAssertTrue(extracted.text.contains("Second page body"))
        // Page markers give the model something to cite.
        XCTAssertTrue(extracted.text.contains("[page 1]"))
        XCTAssertTrue(extracted.text.contains("[page 2]"))
    }

    /// A scan has pages but no text layer. Handing back an empty attachment
    /// would look like it worked; the user needs to be told why it didn't.
    func testScannedPDFIsReportedRatherThanAttachedEmpty() async throws {
        let document = PDFDocument()
        let image = NSImage(size: NSSize(width: 200, height: 200))
        image.lockFocus()
        NSColor.gray.drawSwatch(in: NSRect(x: 0, y: 0, width: 200, height: 200))
        image.unlockFocus()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)

        let url = directory.appendingPathComponent("scan.pdf")
        XCTAssertTrue(document.write(to: url))

        do {
            _ = try await DocumentTextExtractor.extract(from: url)
            XCTFail("A scan has no text to read")
        } catch let error as DocumentTextExtractor.ExtractionError {
            XCTAssertEqual(error, .scannedPDF("scan.pdf"))
            XCTAssertTrue(
                error.errorDescription?.contains("scan") == true,
                "The message has to explain why: \(error.errorDescription ?? "")"
            )
        }
    }

    // MARK: - Word processing

    func testRTFIsReadAsItsPlainText() async throws {
        let attributed = NSAttributedString(
            string: "A Word-ish document with body text.",
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        )
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let url = directory.appendingPathComponent("letter.rtf")
        try data.write(to: url)

        let extracted = try await DocumentTextExtractor.extract(from: url)
        XCTAssertEqual(extracted.kind, .wordProcessing)
        XCTAssertTrue(extracted.text.contains("body text"), "Got: \(extracted.text)")
        // The formatting is presentation; only the words go to the model.
        XCTAssertFalse(extracted.text.contains("\\rtf"))
    }

    // MARK: - Spreadsheets

    /// Builds a real `.xlsx` — a ZIP of XML — to exercise the archive reader
    /// rather than a stand-in for it.
    private func makeXLSX(to name: String) throws -> URL {
        let sharedStrings = """
        <?xml version="1.0"?><sst><si><t>Region</t></si><si><t>Revenue</t></si><si><t>EMEA</t></si></sst>
        """
        let sheet = """
        <?xml version="1.0"?><worksheet><sheetData>\
        <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>\
        <row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>1204</v></c></row>\
        </sheetData></worksheet>
        """

        let url = directory.appendingPathComponent(name)
        try ZIPWriter.write(
            entries: [
                ("xl/sharedStrings.xml", Data(sharedStrings.utf8)),
                ("xl/worksheets/sheet1.xml", Data(sheet.utf8))
            ],
            to: url
        )
        return url
    }

    func testXLSXCellsAreReadThroughSharedStrings() async throws {
        let url = try makeXLSX(to: "figures.xlsx")
        let extracted = try await DocumentTextExtractor.extract(from: url)

        XCTAssertEqual(extracted.kind, .spreadsheet)
        XCTAssertEqual(extracted.structureSummary, "1 sheet")
        // A cell holding text is only a number until the shared-string table
        // is resolved, so this is the part that actually proves it works.
        XCTAssertTrue(extracted.text.contains("Region"), "Got: \(extracted.text)")
        XCTAssertTrue(extracted.text.contains("EMEA"))
        XCTAssertTrue(extracted.text.contains("1204"))
    }

    func testZIPArchiveReadsStoredAndDeflatedEntries() throws {
        // Long, repetitive content compresses; short content is stored as-is.
        // Both paths have to work.
        let repetitive = String(repeating: "markowski ", count: 400)
        let url = directory.appendingPathComponent("mixed.zip")
        try ZIPWriter.write(
            entries: [("big.txt", Data(repetitive.utf8)), ("small.txt", Data("hi".utf8))],
            to: url
        )

        let archive = try XCTUnwrap(ZIPArchive(data: try Data(contentsOf: url)))
        XCTAssertEqual(
            String(data: try XCTUnwrap(archive.contents(of: "big.txt")), encoding: .utf8),
            repetitive
        )
        XCTAssertEqual(
            String(data: try XCTUnwrap(archive.contents(of: "small.txt")), encoding: .utf8),
            "hi"
        )
        XCTAssertNil(archive.contents(of: "absent.txt"))
    }

    // MARK: - Limits and prompt shape

    func testOverlongFileIsTruncatedVisibly() async throws {
        let url = try write(
            String(repeating: "word ", count: DocumentTextExtractor.characterLimit),
            to: "huge.txt"
        )
        let extracted = try await DocumentTextExtractor.extract(from: url)

        XCTAssertTrue(extracted.isTruncated, "The user has to be told it didn't all fit")
        XCTAssertEqual(extracted.text.count, DocumentTextExtractor.characterLimit)
        XCTAssertTrue(extracted.summary.contains("shortened"))
    }

    func testPromptRepresentationLabelsTheFile() {
        let document = ExtractedDocument(
            fileName: "q3.pdf",
            kind: .pdf,
            text: "Revenue rose.",
            byteCount: 2048,
            structureSummary: "12 pages",
            isTruncated: true
        )

        let prompt = document.promptRepresentation
        XCTAssertTrue(prompt.contains("name=\"q3.pdf\""))
        XCTAssertTrue(prompt.contains("type=\"PDF\""))
        XCTAssertTrue(prompt.contains("detail=\"12 pages\""))
        XCTAssertTrue(prompt.contains("shortened"), "The model should know it isn't the whole file")
        XCTAssertTrue(prompt.contains("Revenue rose."))
    }

    func testSupportedTypesCoverWhatTheMenuPromises() {
        for name in ["a.pdf", "b.docx", "c.xlsx", "d.csv", "e.txt", "f.md", "g.rtf"] {
            XCTAssertTrue(
                DocumentTextExtractor.isSupported(url: URL(fileURLWithPath: "/tmp/\(name)")),
                "\(name) should be attachable"
            )
        }
        XCTAssertFalse(DocumentTextExtractor.isSupported(url: URL(fileURLWithPath: "/tmp/x.dmg")))
    }

    /// Source files are text, and a hardcoded language list will always be
    /// missing somebody's. Anything the system already recognises as text or
    /// source has to be accepted too.
    func testCodeFilesOfEveryKindAreAttachable() {
        let languages = [
            "main.py", "App.tsx", "index.jsx", "server.ts", "lib.rs", "Main.java",
            "app.rb", "handler.go", "View.swift", "styles.scss", "config.yaml",
            "schema.graphql", "query.sql", "Component.vue", "page.svelte",
            "script.sh", "data.json", "build.gradle", "notebook.jl", "main.zig"
        ]
        for name in languages {
            XCTAssertTrue(
                DocumentTextExtractor.isSupported(url: URL(fileURLWithPath: "/tmp/\(name)")),
                "\(name) is a text file and should be attachable"
            )
        }

        // Extensionless files people actually have in repositories.
        for name in ["Dockerfile", "Makefile", "LICENSE"] {
            XCTAssertTrue(
                DocumentTextExtractor.isSupported(url: URL(fileURLWithPath: "/tmp/\(name)")),
                "\(name) should be attachable"
            )
        }
    }

    func testACodeFileIsReadAndLabelledAsCode() async throws {
        let source = """
        def calculate(values: list[int]) -> int:
            return sum(values)
        """
        let url = try write(source, to: "metrics.py")
        let extracted = try await DocumentTextExtractor.extract(from: url)

        XCTAssertEqual(extracted.kind, .sourceCode)
        XCTAssertEqual(extracted.structureSummary, "py")
        XCTAssertTrue(extracted.text.contains("def calculate"), "Got: \(extracted.text)")
        // Indentation is meaningful in code and must survive.
        XCTAssertTrue(extracted.text.contains("    return sum(values)"))
        XCTAssertTrue(extracted.promptRepresentation.contains("type=\"Code\""))
    }

    func testTSXIsReadEvenThoughTheSystemHasNoTypeForIt() async throws {
        let url = try write("export const App = () => <div>hi</div>;", to: "App.tsx")
        let extracted = try await DocumentTextExtractor.extract(from: url)

        XCTAssertEqual(extracted.kind, .sourceCode)
        XCTAssertTrue(extracted.text.contains("<div>hi</div>"))
    }
}

/// Writes a ZIP so the tests can build a real `.xlsx`. Test-only: it stores
/// entries uncompressed, which is a valid ZIP and exercises the reader's
/// stored-entry path, plus a deflated one for the compressed path.
private enum ZIPWriter {
    static func write(entries: [(String, Data)], to url: URL) throws {
        var archive = Data()
        var directory = Data()
        var offset = 0

        for (name, contents) in entries {
            let nameBytes = Data(name.utf8)
            let crc = crc32(contents)

            var local = Data()
            local.append(uint32: 0x0403_4b50)
            local.append(uint16: 20)
            local.append(uint16: 0)
            local.append(uint16: 0)          // stored
            local.append(uint16: 0)
            local.append(uint16: 0)
            local.append(uint32: crc)
            local.append(uint32: UInt32(contents.count))
            local.append(uint32: UInt32(contents.count))
            local.append(uint16: UInt16(nameBytes.count))
            local.append(uint16: 0)
            local.append(nameBytes)
            local.append(contents)

            var entry = Data()
            entry.append(uint32: 0x0201_4b50)
            entry.append(uint16: 20)
            entry.append(uint16: 20)
            entry.append(uint16: 0)
            entry.append(uint16: 0)
            entry.append(uint16: 0)
            entry.append(uint16: 0)
            entry.append(uint32: crc)
            entry.append(uint32: UInt32(contents.count))
            entry.append(uint32: UInt32(contents.count))
            entry.append(uint16: UInt16(nameBytes.count))
            entry.append(uint16: 0)
            entry.append(uint16: 0)
            entry.append(uint16: 0)
            entry.append(uint16: 0)
            entry.append(uint32: 0)
            entry.append(uint32: UInt32(offset))
            entry.append(nameBytes)

            archive.append(local)
            directory.append(entry)
            offset += local.count
        }

        let directoryOffset = archive.count
        archive.append(directory)

        var end = Data()
        end.append(uint32: 0x0605_4b50)
        end.append(uint16: 0)
        end.append(uint16: 0)
        end.append(uint16: UInt16(entries.count))
        end.append(uint16: UInt16(entries.count))
        end.append(uint32: UInt32(directory.count))
        end.append(uint32: UInt32(directoryOffset))
        end.append(uint16: 0)
        archive.append(end)

        try archive.write(to: url)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var table: [UInt32] = (0..<256).map { index in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    mutating func append(uint32 value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }
}
