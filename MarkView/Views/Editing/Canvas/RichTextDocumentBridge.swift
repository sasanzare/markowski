import AppKit
import Foundation

/// The bridge between [RichDocument] and the text storage the canvas edits.
///
/// The model is projected into an `NSAttributedString` where block structure
/// lives in *attributes*, not in visible syntax: a heading is a paragraph with
/// heading typography and a `.mvParagraph` descriptor, never `## `. Reading it
/// back reconstructs the model exactly, which is what lets `NSTextView` be the
/// live editing surface without Markdown ever appearing in it.

extension NSAttributedString.Key {
    /// Identifies which block, and which part of it, a paragraph belongs to.
    static let mvParagraph = NSAttributedString.Key("mvParagraph")
    /// Marks generated text (a bullet, a number, a checkbox) that is chrome
    /// rather than content, so reading strips it and editing can protect it.
    static let mvDecoration = NSAttributedString.Key("mvDecoration")
    /// The *semantic* inline style of a run, as an `InlineStyle` raw value.
    ///
    /// Fonts are presentation: a heading and a table header are drawn bold
    /// because of what they are, not because their text is bold. Inferring
    /// style from font traits therefore read that typography back as content
    /// and turned every heading into `**Heading**`. Meaning gets its own
    /// channel; the font stays free to look like whatever the theme wants.
    static let mvInlineStyle = NSAttributedString.Key("mvInlineStyle")
}

/// What one paragraph in the text storage represents.
enum ParagraphRole: Equatable {
    case paragraph
    case heading(level: Int)
    case listItem(ordered: Bool, indent: Int, checkbox: Bool?, ordinal: Int, itemID: UUID)
    case quote
    case code(language: String?)
    case divider
    case raw
    /// A whole table, held by an attachment in a single paragraph.
    case table
}

/// Attached to every paragraph. `NSAttributedString` attribute values are held
/// as objects, so this is a reference type.
final class ParagraphDescriptor: NSObject, NSCopying {
    let blockID: UUID
    let role: ParagraphRole
    /// Index of this paragraph within its block, for blocks that span several
    /// (a list, a table, a multi-line code block).
    let lineIndex: Int

    init(blockID: UUID, role: ParagraphRole, lineIndex: Int = 0) {
        self.blockID = blockID
        self.role = role
        self.lineIndex = lineIndex
    }

    func copy(with zone: NSZone? = nil) -> Any { self }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ParagraphDescriptor else { return false }
        return blockID == other.blockID && role == other.role && lineIndex == other.lineIndex
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(blockID)
        hasher.combine(lineIndex)
        return hasher.finalize()
    }
}


// MARK: - Tables as embedded objects

/// Carries a `TableBlock` into the text storage as a single attachment
/// character, so the table is an object in the document rather than rows of
/// tab-separated text pretending to be one.
final class TableAttachment: NSTextAttachment {
    var table: TableBlock
    let blockID: UUID
    var theme: DocumentTheme
    /// Set by the canvas after projection, so edits inside the grid — which
    /// never reach the outer text view's change hooks — still reach the model.
    var onChange: ((UUID, TableBlock) -> Void)?
    /// Forwarded from the grid, so the formatting panel can follow the caret
    /// into a table.
    var onSelectionChange: ((DocumentTableView, TableEditingContext?) -> Void)?

    init(table: TableBlock, blockID: UUID, theme: DocumentTheme) {
        self.table = table
        self.blockID = blockID
        self.theme = theme
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewProvider(
        for parentView: NSView?,
        location: NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = TableAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

final class TableAttachmentViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? TableAttachment else {
            view = NSView()
            return
        }

        let grid = DocumentTableView(
            table: attachment.table,
            blockID: attachment.blockID,
            theme: attachment.theme
        )
        grid.onChange = { [weak attachment] blockID, table in
            // The attachment holds the authoritative copy, so a later read of
            // the storage sees the edit.
            attachment?.table = table
            attachment?.onChange?(blockID, table)
        }
        grid.onSelectionChange = { [weak attachment] grid, context in
            attachment?.onSelectionChange?(grid, context)
        }
        view = grid
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let width = max(240, textContainer?.size.width ?? proposedLineFragment.width)
        guard let grid = view as? DocumentTableView else {
            return CGRect(x: 0, y: 0, width: width, height: 44)
        }

        grid.frame = NSRect(x: 0, y: 0, width: width, height: grid.measuredHeight(for: width))
        grid.layoutSubtreeIfNeeded()
        return CGRect(x: 0, y: 0, width: width, height: grid.measuredHeight(for: width))
    }
}

/// A picture standing on its own line, shown as the picture rather than as
/// `![alt](path)`.
///
/// Markdown models an image as a link with a `!` in front, so without this the
/// canvas — whose whole point is never showing syntax — displayed an inserted
/// image as the characters "!alt". The attachment carries the pieces it was
/// built from, so reading the storage back reproduces exactly the same
/// Markdown.
final class DocumentImageAttachment: NSTextAttachment {
    let source: String
    let alt: String

    /// Longest edge on screen. A full-resolution screenshot would otherwise
    /// push everything else off the page.
    private let maximumEdge: CGFloat = 420

    init(source: String, alt: String, baseURL: URL?) {
        self.source = source
        self.alt = alt
        super.init(data: nil, ofType: nil)

        guard let url = Self.resolve(source: source, baseURL: baseURL),
              let loaded = NSImage(contentsOf: url) else {
            return
        }
        image = loaded
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func resolve(source: String, baseURL: URL?) -> URL? {
        guard !source.isEmpty else { return nil }
        if let remote = URL(string: source), remote.scheme == "http" || remote.scheme == "https" {
            return nil
        }

        let expanded = (source as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded) }
        return baseURL?.appendingPathComponent(expanded)
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else {
            // Nothing loaded: leave room for the placeholder chip.
            return CGRect(x: 0, y: 0, width: 220, height: 34)
        }

        let available = min(
            maximumEdge,
            max(80, (textContainer?.size.width ?? proposedLineFragment.width) - 8)
        )
        let scale = min(1, available / image.size.width)
        return CGRect(
            x: 0,
            y: 0,
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }
}

// MARK: - Theme

/// Typography per block kind. This is the difference between a document and a
/// text file: real heading sizes, real spacing, real indents.
struct DocumentTheme {
    var bodySize: CGFloat = 14
    var lineSpacing: CGFloat = 3.5
    var paragraphSpacing: CGFloat = 12
    var listIndent: CGFloat = 22
    var quoteIndent: CGFloat = 18
    var codeSize: CGFloat = 12.5
    var tableCellSpacing: CGFloat = 150

    static let standard = DocumentTheme()

    func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return bodySize * 1.9
        case 2: return bodySize * 1.5
        case 3: return bodySize * 1.25
        case 4: return bodySize * 1.1
        default: return bodySize
        }
    }

    func headingSpacingBefore(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 8
        case 2: return 22
        default: return 16
        }
    }
}

// MARK: - Rendering the model into text

enum RichTextRenderer {

    /// Separates paragraphs. One `\n` per paragraph, so paragraph indices in
    /// the storage map one-to-one onto lines.
    static let paragraphSeparator = "\n"

    /// Where relative image paths resolve from — the folder holding the
    /// document being edited.
    static var imageBaseURL: URL?

    static func attributedString(
        for document: RichDocument,
        theme: DocumentTheme = .standard
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for block in document.blocks {
            let rendered = attributedString(for: block, theme: theme)
            if result.length > 0 {
                result.append(NSAttributedString(string: paragraphSeparator))
            }
            result.append(rendered)
        }
        return result
    }

    /// Markdown writes an image as a `!` followed by a link, so a paragraph
    /// that is exactly those two runs *is* a standalone image.
    static func standaloneImage(in text: InlineText) -> (source: String, alt: String)? {
        let runs = text.normalized().runs
        guard runs.count == 2,
              runs[0].text == "!", runs[0].link == nil,
              let source = runs[1].link, !source.isEmpty else {
            return nil
        }
        return (source, runs[1].text)
    }

    static func attributedString(for block: RichBlock, theme: DocumentTheme) -> NSAttributedString {
        switch block.content {
        case .paragraph(let text):
            let descriptor = ParagraphDescriptor(blockID: block.id, role: .paragraph)
            if let image = standaloneImage(in: text) {
                return imageParagraph(image, descriptor: descriptor, theme: theme)
            }
            return paragraph(text, descriptor: descriptor, theme: theme)

        case .heading(let level, let text):
            return paragraph(
                text,
                descriptor: ParagraphDescriptor(blockID: block.id, role: .heading(level: level)),
                theme: theme
            )

        case .list(let style, let items):
            let result = NSMutableAttributedString()
            var ordinal: Int
            if case .ordered(let start) = style { ordinal = start } else { ordinal = 1 }

            for (index, item) in items.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: paragraphSeparator)) }

                let isOrdered: Bool
                if case .ordered = style { isOrdered = true } else { isOrdered = false }

                let descriptor = ParagraphDescriptor(
                    blockID: block.id,
                    role: .listItem(
                        ordered: isOrdered,
                        indent: item.indent,
                        checkbox: item.checkbox,
                        ordinal: ordinal,
                        itemID: item.id
                    ),
                    lineIndex: index
                )
                result.append(listItem(item, descriptor: descriptor, ordinal: ordinal, theme: theme))
                if isOrdered { ordinal += 1 }
            }
            return result

        case .quote(let blocks):
            let result = NSMutableAttributedString()
            for (index, inner) in blocks.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: paragraphSeparator)) }
                let descriptor = ParagraphDescriptor(blockID: block.id, role: .quote, lineIndex: index)
                result.append(paragraph(
                    InlineText(plain: inner.plainText),
                    descriptor: descriptor,
                    theme: theme
                ))
            }
            return result

        case .code(let language, let text):
            let lines = text.components(separatedBy: "\n")
            let result = NSMutableAttributedString()
            for (index, line) in lines.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: paragraphSeparator)) }
                let descriptor = ParagraphDescriptor(
                    blockID: block.id,
                    role: .code(language: language),
                    lineIndex: index
                )
                result.append(codeLine(line, descriptor: descriptor, theme: theme))
            }
            return result

        case .table(let table):
            let descriptor = ParagraphDescriptor(blockID: block.id, role: .table)
            let attachment = TableAttachment(table: table, blockID: block.id, theme: theme)
            let result = NSMutableAttributedString(attachment: attachment)

            let style = NSMutableParagraphStyle()
            style.paragraphSpacingBefore = theme.paragraphSpacing
            style.paragraphSpacing = theme.paragraphSpacing
            result.addAttributes([
                .paragraphStyle: style,
                .mvParagraph: descriptor
            ], range: result.fullRange)
            return result

        case .divider:
            let descriptor = ParagraphDescriptor(blockID: block.id, role: .divider)
            // A rule has no text of its own; a thin run of spaces carries the
            // paragraph so it can hold a border and still be selectable.
            let attributed = NSMutableAttributedString(string: " ")
            attributed.addAttributes(dividerAttributes(theme: theme, descriptor: descriptor), range: attributed.fullRange)
            attributed.addAttribute(.mvDecoration, value: true, range: attributed.fullRange)
            return attributed

        case .raw(let text):
            let lines = text.components(separatedBy: "\n")
            let result = NSMutableAttributedString()
            for (index, line) in lines.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: paragraphSeparator)) }
                let descriptor = ParagraphDescriptor(blockID: block.id, role: .raw, lineIndex: index)
                result.append(codeLine(line, descriptor: descriptor, theme: theme, isRaw: true))
            }
            return result
        }
    }

    // MARK: - Paragraph builders

    private static func paragraph(
        _ text: InlineText,
        descriptor: ParagraphDescriptor,
        theme: DocumentTheme
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let plain = text.plainText
        let isRTL = TextDirection.isRightToLeft(plain)

        for run in text.runs {
            result.append(NSAttributedString(string: run.text, attributes: inlineAttributes(
                run, descriptor: descriptor, theme: theme, isRTL: isRTL
            )))
        }

        // An empty paragraph still needs its attributes, or typing into it
        // would inherit whatever came before.
        if result.length == 0 {
            let style = paragraphStyle(for: descriptor.role, theme: theme, isRTL: isRTL)
            return NSAttributedString(string: "", attributes: [
                .font: baseFont(for: descriptor.role, theme: theme, text: ""),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
                .mvParagraph: descriptor
            ])
        }

        result.addAttribute(
            .paragraphStyle,
            value: paragraphStyle(for: descriptor.role, theme: theme, isRTL: isRTL),
            range: result.fullRange
        )
        result.addAttribute(.mvParagraph, value: descriptor, range: result.fullRange)
        return result
    }

    private static func imageParagraph(
        _ image: (source: String, alt: String),
        descriptor: ParagraphDescriptor,
        theme: DocumentTheme
    ) -> NSAttributedString {
        let attachment = DocumentImageAttachment(
            source: image.source,
            alt: image.alt,
            baseURL: imageBaseURL
        )
        let result = NSMutableAttributedString(attachment: attachment)

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = theme.paragraphSpacing
        style.paragraphSpacing = theme.paragraphSpacing

        var attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: style,
            .mvParagraph: descriptor
        ]
        // An image that could not be loaded still has to read as an image
        // rather than as an empty gap.
        if attachment.image == nil {
            attributes[.font] = NSFont.systemFont(ofSize: theme.bodySize)
            attributes[.foregroundColor] = NSColor.secondaryLabelColor
            attributes[.toolTip] = "Couldn’t find “\(image.source)”"
        }
        result.addAttributes(attributes, range: result.fullRange)
        return result
    }

    private static func listItem(
        _ item: ListItem,
        descriptor: ParagraphDescriptor,
        ordinal: Int,
        theme: DocumentTheme
    ) -> NSAttributedString {
        let plain = item.content.plainText
        let isRTL = TextDirection.isRightToLeft(plain)
        let result = NSMutableAttributedString()

        // The marker is generated chrome: tagged so reading strips it and
        // editing can refuse to break it.
        let markerText = marker(for: descriptor.role, ordinal: ordinal) + "\t"
        result.append(NSAttributedString(string: markerText, attributes: [
            .font: MarkowskiTypography.font(size: theme.bodySize, weight: .regular, for: plain),
            .foregroundColor: NSColor.secondaryLabelColor,
            .mvDecoration: true
        ]))

        for run in item.content.runs {
            result.append(NSAttributedString(string: run.text, attributes: inlineAttributes(
                run, descriptor: descriptor, theme: theme, isRTL: isRTL
            )))
        }

        result.addAttribute(
            .paragraphStyle,
            value: paragraphStyle(for: descriptor.role, theme: theme, isRTL: isRTL),
            range: result.fullRange
        )
        result.addAttribute(.mvParagraph, value: descriptor, range: result.fullRange)
        return result
    }

    private static func codeLine(
        _ line: String,
        descriptor: ParagraphDescriptor,
        theme: DocumentTheme,
        isRaw: Bool = false
    ) -> NSAttributedString {
        let style = paragraphStyle(for: descriptor.role, theme: theme, isRTL: false)
        return NSAttributedString(string: line, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: theme.codeSize, weight: .regular),
            .foregroundColor: isRaw ? NSColor.secondaryLabelColor : NSColor.labelColor,
            .paragraphStyle: style,
            .mvParagraph: descriptor
        ])
    }

    // MARK: - Attributes

    static func marker(for role: ParagraphRole, ordinal: Int) -> String {
        guard case .listItem(let ordered, _, let checkbox, _, _) = role else { return "" }
        if let checkbox { return checkbox ? "☑" : "☐" }
        return ordered ? "\(ordinal)." : "•"
    }

    static func baseFont(for role: ParagraphRole, theme: DocumentTheme, text: String) -> NSFont {
        switch role {
        case .heading(let level):
            return MarkowskiTypography.font(size: theme.headingSize(level), weight: .bold, for: text)
        case .code, .raw:
            return .monospacedSystemFont(ofSize: theme.codeSize, weight: .regular)
        default:
            return MarkowskiTypography.font(size: theme.bodySize, weight: .regular, for: text)
        }
    }

    private static func inlineAttributes(
        _ run: InlineRun,
        descriptor: ParagraphDescriptor,
        theme: DocumentTheme,
        isRTL: Bool
    ) -> [NSAttributedString.Key: Any] {
        var font: NSFont

        if run.style.contains(.code) {
            font = .monospacedSystemFont(ofSize: theme.codeSize, weight: .regular)
        } else {
            let weight: NSFont.Weight
            if case .heading = descriptor.role {
                weight = .bold
            } else {
                weight = run.style.contains(.bold) ? .bold : .regular
            }
            font = baseFont(for: descriptor.role, theme: theme, text: run.text)
            if weight == .bold || run.style.contains(.bold) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            }
            if run.style.contains(.italic) {
                font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            }
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .mvParagraph: descriptor,
            .mvInlineStyle: run.style.rawValue
        ]

        if run.style.contains(.strikethrough) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if run.style.contains(.code) {
            attributes[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.14)
        }
        if run.style.contains(.highlight) {
            attributes[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.32)
        }
        if let link = run.link {
            attributes[.link] = link
            attributes[.foregroundColor] = NSColor.linkColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    private static func dividerAttributes(
        theme: DocumentTheme,
        descriptor: ParagraphDescriptor
    ) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = theme.paragraphSpacing
        style.paragraphSpacing = theme.paragraphSpacing
        return [
            .font: NSFont.systemFont(ofSize: 4),
            .paragraphStyle: style,
            .mvParagraph: descriptor,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: NSColor.separatorColor
        ]
    }

    static func paragraphStyle(
        for role: ParagraphRole,
        theme: DocumentTheme,
        isRTL: Bool
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = theme.lineSpacing
        style.paragraphSpacing = theme.paragraphSpacing
        // A paragraph's own text decides its direction, so a Persian paragraph
        // in an English document lays out correctly without any setting.
        style.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
        style.alignment = isRTL ? .right : .left

        switch role {
        case .heading(let level):
            style.paragraphSpacingBefore = theme.headingSpacingBefore(level)
            style.paragraphSpacing = theme.paragraphSpacing * 0.55

        case .listItem(_, let indent, _, _, _):
            let base = theme.listIndent * CGFloat(indent + 1)
            style.firstLineHeadIndent = base - theme.listIndent
            style.headIndent = base
            style.paragraphSpacing = 3
            style.tabStops = [NSTextTab(textAlignment: isRTL ? .right : .left, location: base)]
            style.defaultTabInterval = theme.listIndent

        case .quote:
            style.firstLineHeadIndent = theme.quoteIndent
            style.headIndent = theme.quoteIndent
            style.paragraphSpacing = 4

        case .code, .raw:
            style.lineSpacing = 2
            style.firstLineHeadIndent = 12
            style.headIndent = 12
            style.paragraphSpacing = 0

        case .table:
            style.paragraphSpacingBefore = theme.paragraphSpacing
            style.paragraphSpacing = theme.paragraphSpacing

        case .divider, .paragraph:
            break
        }

        return style
    }
}

// MARK: - Reading the text back into the model

enum RichTextReader {

    /// Reconstructs the document from the text storage.
    ///
    /// Paragraph descriptors carry the structure, so this is exact rather than
    /// a re-parse — which is the point: what the user edited *is* the document,
    /// not a rendering of one.
    static func document(from attributed: NSAttributedString) -> RichDocument {
        let paragraphs = split(attributed)
        var blocks: [RichBlock] = []

        var index = 0
        while index < paragraphs.count {
            let paragraph = paragraphs[index]
            guard let descriptor = paragraph.descriptor else {
                // Text typed with no descriptor (a brand-new paragraph) is body
                // text; that is the only sensible default.
                blocks.append(RichBlock(content: .paragraph(inlineText(from: paragraph.attributed))))
                index += 1
                continue
            }

            // Gather every consecutive paragraph belonging to the same block.
            var group: [Paragraph] = [paragraph]
            var next = index + 1
            while next < paragraphs.count,
                  let nextDescriptor = paragraphs[next].descriptor,
                  nextDescriptor.blockID == descriptor.blockID,
                  sameBlockRole(descriptor.role, nextDescriptor.role) {
                group.append(paragraphs[next])
                next += 1
            }
            index = next

            blocks.append(block(from: group, descriptor: descriptor))
        }

        return RichDocument(blocks: blocks).normalized()
    }

    struct Paragraph {
        let attributed: NSAttributedString
        let descriptor: ParagraphDescriptor?
    }

    static func split(_ attributed: NSAttributedString) -> [Paragraph] {
        let text = attributed.string as NSString
        var result: [Paragraph] = []
        var start = 0

        while start <= text.length {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: start, length: 0))

            let range = NSRange(location: start, length: contentsEnd - start)
            let piece = attributed.attributedSubstring(from: range)
            let descriptor = piece.length > 0
                ? piece.attribute(.mvParagraph, at: 0, effectiveRange: nil) as? ParagraphDescriptor
                : attributed.paragraphDescriptor(at: start)
            result.append(Paragraph(attributed: piece, descriptor: descriptor))

            if lineEnd == start { break }
            start = lineEnd
            if start >= text.length { break }
        }
        return result
    }

    private static func sameBlockRole(_ lhs: ParagraphRole, _ rhs: ParagraphRole) -> Bool {
        switch (lhs, rhs) {
        case (.listItem, .listItem), (.code, .code),
             (.quote, .quote), (.raw, .raw):
            return true
        default:
            return false
        }
    }

    private static func block(from group: [Paragraph], descriptor: ParagraphDescriptor) -> RichBlock {
        switch descriptor.role {
        case .paragraph:
            return RichBlock(id: descriptor.blockID, content: .paragraph(inlineText(from: group[0].attributed)))

        case .heading(let level):
            return RichBlock(
                id: descriptor.blockID,
                content: .heading(level: level, content: inlineText(from: group[0].attributed))
            )

        case .listItem(let ordered, _, _, let ordinal, _):
            var items: [ListItem] = []
            for paragraph in group {
                guard case .listItem(_, let indent, let checkbox, _, let itemID) =
                        paragraph.descriptor?.role ?? descriptor.role else { continue }
                items.append(ListItem(
                    id: itemID,
                    content: inlineText(from: paragraph.attributed),
                    indent: indent,
                    checkbox: checkbox
                ))
            }
            return RichBlock(
                id: descriptor.blockID,
                content: .list(style: ordered ? .ordered(start: ordinal) : .bulleted, items: items)
            )

        case .quote:
            let blocks = group.map {
                RichBlock(content: .paragraph(inlineText(from: $0.attributed)))
            }
            return RichBlock(id: descriptor.blockID, content: .quote(blocks: blocks))

        case .code(let language):
            let text = group.map { stripDecoration($0.attributed).string }.joined(separator: "\n")
            return RichBlock(id: descriptor.blockID, content: .code(language: language, text: text))

        case .raw:
            let text = group.map { stripDecoration($0.attributed).string }.joined(separator: "\n")
            return RichBlock(id: descriptor.blockID, content: .raw(text))

        case .divider:
            return RichBlock(id: descriptor.blockID, content: .divider)

        case .table:
            // The attachment holds the live table, so this is a read of the
            // model rather than a re-parse of anything.
            let attributed = group[0].attributed
            var found: TableBlock?
            attributed.enumerateAttribute(.attachment, in: attributed.fullRange, options: []) { value, _, stop in
                if let attachment = value as? TableAttachment {
                    found = attachment.table
                    stop.pointee = true
                }
            }
            guard let table = found else {
                return RichBlock(id: descriptor.blockID, content: .paragraph(InlineText()))
            }
            return RichBlock(id: descriptor.blockID, content: .table(table))
        }
    }

    private static func stripDecoration(_ attributed: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        attributed.enumerateAttributes(in: attributed.fullRange, options: []) { attributes, range, _ in
            guard attributes[.mvDecoration] == nil else { return }
            result.append(attributed.attributedSubstring(from: range))
        }
        return result
    }

    /// Turns styled text back into runs. Styles are read from the *fonts and
    /// attributes*, which is where the editor put them.
    static func inlineText(
        from attributed: NSAttributedString,
        baseIsBold: Bool = false,
        baseIsMonospaced: Bool = false
    ) -> InlineText {
        let content = stripDecoration(attributed)
        var runs: [InlineRun] = []

        content.enumerateAttributes(in: content.fullRange, options: []) { attributes, range, _ in
            // An image is held as an attachment; put back the two runs it was
            // built from so it serialises to the same `![alt](src)`.
            if let image = attributes[.attachment] as? DocumentImageAttachment {
                runs.append(InlineRun("!"))
                runs.append(InlineRun(image.alt, link: image.source))
                return
            }

            let text = content.attributedSubstring(from: range).string
            guard !text.isEmpty else { return }

            var style: InlineStyle
            if let raw = attributes[.mvInlineStyle] as? Int {
                style = InlineStyle(rawValue: raw)
            } else {
                // Text with no semantic attribute was typed rather than
                // projected; its font traits are the only signal there is.
                style = []
                if let font = attributes[.font] as? NSFont {
                    let traits = NSFontManager.shared.traits(of: font)
                    if traits.contains(.boldFontMask), !baseIsBold { style.insert(.bold) }
                    if traits.contains(.italicFontMask) { style.insert(.italic) }
                    if font.fontDescriptor.symbolicTraits.contains(.monoSpace), !baseIsMonospaced {
                        style.insert(.code)
                    }
                }
                if let value = attributes[.strikethroughStyle] as? Int, value != 0 {
                    style.insert(.strikethrough)
                }
            }

            let link = attributes[.link].flatMap { value -> String? in
                if let url = value as? URL { return url.absoluteString }
                return value as? String
            }

            runs.append(InlineRun(text, style: style, link: link))
        }

        return InlineText(runs).normalized()
    }
}

extension NSAttributedString {
    var fullRange: NSRange { NSRange(location: 0, length: length) }

    /// The descriptor governing an insertion point, including at the very end
    /// of the storage where there is no character to read from.
    func paragraphDescriptor(at location: Int) -> ParagraphDescriptor? {
        guard length > 0 else { return nil }
        let index = min(max(location, 0), length - 1)
        return attribute(.mvParagraph, at: index, effectiveRange: nil) as? ParagraphDescriptor
    }
}
