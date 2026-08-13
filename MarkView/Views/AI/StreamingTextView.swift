import AppKit
import CoreText
import SwiftUI

enum TextDirection {
    static func isRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            guard CharacterSet.letters.contains(scalar) else { continue }
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF:
                return true
            case 0x0041...0x005A, 0x0061...0x007A:
                return false
            default:
                continue
            }
        }
        return false
    }
}

enum MarkowskiTypography {
    private static var didRegisterFonts = false

    static func font(size: CGFloat, weight: NSFont.Weight, for text: String) -> NSFont {
        guard TextDirection.isRightToLeft(text) else {
            return .systemFont(ofSize: size, weight: weight)
        }

        registerFontsIfNeeded()
        let name: String
        switch weight {
        case ...NSFont.Weight.light: name = "IRANSansX-Light"
        case NSFont.Weight.regular..<NSFont.Weight.semibold: name = "IRANSansX-Regular"
        case NSFont.Weight.semibold..<NSFont.Weight.bold: name = "IRANSansX-DemiBold"
        default: name = "IRANSansX-Bold"
        }
        return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    static func registerFontsIfNeeded() {
        guard !didRegisterFonts else { return }
        didRegisterFonts = true

        let names = ["IRANSansX-Light", "IRANSansX-Regular", "IRANSansX-DemiBold", "IRANSansX-Bold"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "fonts") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

struct StreamingTextView: View {
    let fullText: String
    let isGenerating: Bool
    /// Reports text the user selected inside this reply, so the composer can
    /// pin it as context the same way a document selection is pinned.
    var onSelectionChanged: ((String) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var animator = MarkdownRevealAnimator()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MarkdownBlocksView(markdown: animator.visibleText, onSelectionChanged: onSelectionChanged)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isGenerating {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: 2, height: 14)
                    .opacity(reduceMotion ? 1 : 0.8)
            }
        }
        .onAppear {
            // A word reveal communicates response progress rather than adding
            // decorative spatial motion, so keep it available with Reduce
            // Motion enabled as well. A response that already finished is not
            // progress though — replaying the typewriter made every completed
            // answer dribble back in, so those land whole.
            animator.update(target: fullText, animate: isGenerating)
        }
        .onChange(of: fullText) { _, newText in
            animator.update(target: newText, animate: isGenerating)
        }
        .onChange(of: isGenerating) { _, generating in
            if !generating {
                animator.update(target: fullText, animate: false)
            }
        }
        .onDisappear {
            animator.cancel()
        }
    }
}

/// `AttributedString(markdown:)` parses block structure but `Text` renders it
/// as a single run-on paragraph — headings, list items, and code blocks all
/// collapse onto one line. Splitting the source into blocks first and parsing
/// only inline syntax within each one keeps the assistant's Markdown readable.
struct MarkdownBlocksView: View {
    let markdown: String
    var onSelectionChanged: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(MarkdownBlock.parse(markdown)) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            selectableText(
                block.text,
                font: MarkowskiTypography.font(
                    size: level <= 1 ? 15 : level == 2 ? 14 : 13,
                    weight: .semibold,
                    for: block.text
                )
            )
            .padding(.top, 2)

        case .paragraph:
            selectableText(block.text)

        case .listItem(let marker, let indent):
            let isRTL = TextDirection.isRightToLeft(block.text)
            HStack(alignment: .top, spacing: 7) {
                if !isRTL {
                    listMarker(marker, isRTL: false)
                }
                selectableText(block.text)
                    .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                if isRTL {
                    listMarker(marker, isRTL: true)
                }
            }
            .padding(.leading, CGFloat(indent) * 14)

        case .quote:
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 2)
                selectableText(block.text, color: .secondaryLabelColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let language):
            SyntaxCodeBlock(text: block.text, language: language, onSelectionChanged: onSelectionChanged)

        case .rule:
            Divider()
        }
    }

    private func listMarker(_ marker: String, isRTL: Bool) -> some View {
        let displayedMarker = marker.hasSuffix(".") && isRTL
            ? "." + String(marker.dropLast())
            : marker
        return Text(displayedMarker)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.top, 1.5)
        .frame(minWidth: marker == "•" ? 8 : 22, alignment: .trailing)
    }


    private func selectableText(
        _ text: String,
        font: NSFont? = nil,
        color: NSColor = .labelColor,
        parseInlineMarkdown: Bool = true
    ) -> some View {
        SelectableMarkdownText(
            text: text,
            font: font ?? MarkowskiTypography.font(size: 13, weight: .regular, for: text),
            color: color,
            parseInlineMarkdown: parseInlineMarkdown,
            onSelectionChanged: onSelectionChanged
        )
    }
}

/// A read-only `NSTextView` rather than SwiftUI `Text`, because SwiftUI offers
/// no way to *read* what the user selected — and asking about a passage of a
/// reply is exactly what the composer needs it for.
struct SelectableMarkdownText: NSViewRepresentable {
    let text: String
    let font: NSFont
    let color: NSColor
    var parseInlineMarkdown: Bool = true
    var syntaxLanguage: String?
    var onSelectionChanged: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> MessageTextView {
        let textView = MessageTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.delegate = context.coordinator
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        apply(to: textView)
        return textView
    }

    func updateNSView(_ textView: MessageTextView, context: Context) {
        context.coordinator.parent = self
        apply(to: textView)
    }

    private func apply(to textView: MessageTextView) {
        let rendered = attributedText()
        if textView.textStorage?.isEqual(to: rendered) != true {
            textView.textStorage?.setAttributedString(rendered)
            textView.invalidateIntrinsicContentSize()
        }
    }

    private func attributedText() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.1
        let isRTL = TextDirection.isRightToLeft(text)
        paragraph.baseWritingDirection = isRTL ? .rightToLeft : .leftToRight
        paragraph.alignment = isRTL ? .right : .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        if let syntaxLanguage {
            return SyntaxHighlighter.highlight(
                text,
                language: syntaxLanguage,
                font: font,
                paragraphStyle: paragraph
            )
        }

        guard parseInlineMarkdown else {
            return NSAttributedString(string: text, attributes: attributes)
        }

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: attributes)
        }

        let result = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        let fullRange = NSRange(location: 0, length: result.length)
        // Keep the Markdown parser's bold/italic traits while imposing this
        // block's size, colour, and line spacing.
        let overrides: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        result.addAttributes(overrides, range: fullRange)
        result.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let traits = (value as? NSFont).map {
                NSFontManager.shared.traits(of: $0)
            } ?? []
            var merged = NSFontManager.shared.convert(font, toHaveTrait: traits)
            if merged.pointSize != font.pointSize {
                merged = NSFont(descriptor: merged.fontDescriptor, size: font.pointSize) ?? font
            }
            result.addAttribute(.font, value: merged, range: range)
        }
        return result
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableMarkdownText

        init(_ parent: SelectableMarkdownText) {
            self.parent = parent
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }

            let selected = (textView.string as NSString).substring(with: range)
            guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            parent.onSelectionChanged?(selected)
        }
    }
}

private struct SyntaxCodeBlock: View {
    let text: String
    let language: String?
    var onSelectionChanged: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = language, !label.isEmpty {
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .tracking(0.55)
                    .foregroundStyle(Color(nsColor: SyntaxPalette.comment))
                    .padding(.horizontal, 11)
                    .padding(.top, 9)
                    .padding(.bottom, 3)
            }

            SelectableMarkdownText(
                text: text,
                font: .monospacedSystemFont(ofSize: 12.2, weight: .regular),
                color: SyntaxPalette.plain,
                parseInlineMarkdown: false,
                syntaxLanguage: language ?? "plain",
                onSelectionChanged: onSelectionChanged
            )
            .padding(.horizontal, 11)
            .padding(.top, language == nil ? 10 : 5)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SyntaxPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(SyntaxPalette.border, lineWidth: 0.75)
        }
        .padding(.vertical, 2)
    }
}

private enum SyntaxPalette {
    private static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static let plain = adaptive(
        light: NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 1),
        dark: NSColor(srgbRed: 0.86, green: 0.88, blue: 0.92, alpha: 1)
    )
    static let keyword = adaptive(
        light: NSColor(srgbRed: 0.62, green: 0.15, blue: 0.64, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.48, blue: 0.70, alpha: 1)
    )
    static let string = adaptive(
        light: NSColor(srgbRed: 0.72, green: 0.22, blue: 0.13, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.52, blue: 0.45, alpha: 1)
    )
    static let number = adaptive(
        light: NSColor(srgbRed: 0.18, green: 0.39, blue: 0.72, alpha: 1),
        dark: NSColor(srgbRed: 0.82, green: 0.75, blue: 0.42, alpha: 1)
    )
    static let type = adaptive(
        light: NSColor(srgbRed: 0.05, green: 0.47, blue: 0.57, alpha: 1),
        dark: NSColor(srgbRed: 0.37, green: 0.85, blue: 1.00, alpha: 1)
    )
    static let function = adaptive(
        light: NSColor(srgbRed: 0.12, green: 0.45, blue: 0.34, alpha: 1),
        dark: NSColor(srgbRed: 0.45, green: 0.82, blue: 0.69, alpha: 1)
    )
    static let comment = adaptive(
        light: NSColor(srgbRed: 0.43, green: 0.47, blue: 0.53, alpha: 1),
        dark: NSColor(srgbRed: 0.50, green: 0.56, blue: 0.63, alpha: 1)
    )
    static let surface = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 0.955, green: 0.96, blue: 0.975, alpha: 1),
        dark: NSColor(srgbRed: 0.075, green: 0.082, blue: 0.10, alpha: 1)
    ))
    static let border = Color(nsColor: adaptive(
        light: NSColor(srgbRed: 0.83, green: 0.85, blue: 0.89, alpha: 1),
        dark: NSColor(srgbRed: 0.22, green: 0.24, blue: 0.29, alpha: 1)
    ))
}

private enum SyntaxHighlighter {
    static func highlight(
        _ source: String,
        language: String,
        font: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source, attributes: [
            .font: font,
            .foregroundColor: SyntaxPalette.plain,
            .paragraphStyle: paragraphStyle
        ])
        let fullRange = NSRange(location: 0, length: result.length)

        apply(#"\b(?:true|false|null|nil|None|self|super)\b"#, color: SyntaxPalette.number, to: result, range: fullRange)
        apply(#"\b\d+(?:\.\d+)?\b"#, color: SyntaxPalette.number, to: result, range: fullRange)
        apply(keywordPattern(for: language), color: SyntaxPalette.keyword, to: result, range: fullRange)
        apply(#"\b[A-Z][A-Za-z0-9_]*\b"#, color: SyntaxPalette.type, to: result, range: fullRange)
        apply(#"\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"#, color: SyntaxPalette.function, to: result, range: fullRange)
        apply(#"(?:\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')"#, color: SyntaxPalette.string, to: result, range: fullRange)
        apply(commentPattern(for: language), color: SyntaxPalette.comment, to: result, range: fullRange)
        return result
    }

    private static func keywordPattern(for language: String) -> String {
        let common = "if|else|for|while|return|break|continue|switch|case|default|try|catch|throw|throws|async|await|import|from|as|in|is|not|and|or"
        let extra: String
        switch language.lowercased() {
        case "swift": extra = "let|var|func|struct|class|enum|protocol|extension|guard|defer|where|some|any|actor|nonisolated|private|public|internal|static"
        case "rust", "rs": extra = "fn|let|mut|struct|enum|trait|impl|pub|crate|mod|use|match|move|ref|where|loop|unsafe|extern|dyn|const|static|type"
        case "python", "py": extra = "def|class|lambda|yield|with|pass|raise|global|nonlocal|elif|except|finally|assert"
        case "javascript", "js", "typescript", "ts", "tsx", "jsx": extra = "const|let|var|function|class|extends|new|this|typeof|instanceof|interface|type|export|async"
        case "json": extra = ""
        default: extra = "const|let|var|func|function|def|class|struct|enum|public|private|static"
        }
        return #"\b(?:"# + common + (extra.isEmpty ? "" : "|" + extra) + #")\b"#
    }

    private static func commentPattern(for language: String) -> String {
        switch language.lowercased() {
        case "python", "py", "ruby", "rb", "shell", "sh", "bash", "yaml", "yml":
            return #"(?m)#.*$"#
        case "html", "xml":
            return #"<!--[\s\S]*?-->"#
        default:
            return #"(?m)//.*$|/\*[\s\S]*?\*/"#
        }
    }

    private static func apply(
        _ pattern: String,
        color: NSColor,
        to result: NSMutableAttributedString,
        range: NSRange
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        for match in regex.matches(in: result.string, range: range) {
            result.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}

/// Sizes itself to its laid-out text so it can live in a SwiftUI stack without
/// a scroll view.
final class MessageTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
    }

    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind: Equatable {
        case heading(level: Int)
        case paragraph
        case listItem(marker: String, indent: Int)
        case quote
        case code(language: String?)
        case rule
    }

    let id: Int
    let kind: Kind
    let text: String

    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var codeLines: [String] = []
        var isInCodeFence = false
        var codeLanguage: String?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(MarkdownBlock(id: blocks.count, kind: .paragraph, text: paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }

        func flushCode() {
            guard !codeLines.isEmpty else { return }
            blocks.append(MarkdownBlock(id: blocks.count, kind: .code(language: codeLanguage), text: codeLines.joined(separator: "\n")))
            codeLines.removeAll()
            codeLanguage = nil
        }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if isInCodeFence {
                    flushCode()
                    isInCodeFence = false
                } else {
                    flushParagraph()
                    isInCodeFence = true
                    let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                    codeLanguage = language.isEmpty ? nil : language.lowercased()
                }
                continue
            }

            if isInCodeFence {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blocks.count, kind: .rule, text: ""))
                continue
            }

            if let level = headingLevel(of: trimmed) {
                flushParagraph()
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(MarkdownBlock(id: blocks.count, kind: .heading(level: level), text: text))
                continue
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                blocks.append(MarkdownBlock(id: blocks.count, kind: .quote, text: String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if let item = listItem(from: line) {
                flushParagraph()
                blocks.append(MarkdownBlock(
                    id: blocks.count,
                    kind: .listItem(marker: item.marker, indent: item.indent),
                    text: item.text
                ))
                continue
            }

            paragraph.append(trimmed)
        }

        // An unterminated fence is normal mid-stream; show what has arrived.
        flushCode()
        flushParagraph()
        return blocks
    }

    private static func headingLevel(of line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }
        guard line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return hashes
    }

    private static func listItem(from line: String) -> (marker: String, indent: Int, text: String)? {
        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        let indent = min(leadingSpaces / 2, 3)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        for bullet in ["- ", "* ", "+ "] {
            if trimmed.hasPrefix(bullet) {
                return ("•", indent, String(trimmed.dropFirst(2)))
            }
        }

        // "1. ", "12) " and friends.
        let digits = trimmed.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let afterDigits = trimmed.dropFirst(digits.count)
        guard afterDigits.hasPrefix(". ") || afterDigits.hasPrefix(") ") else { return nil }
        return ("\(digits).", indent, String(afterDigits.dropFirst(2)))
    }
}

@MainActor
private final class MarkdownRevealAnimator: ObservableObject {
    @Published private(set) var visibleText = ""

    private var targetText = ""
    private var revealTask: Task<Void, Never>?

    func update(target: String, animate: Bool) {
        targetText = target

        guard animate else {
            revealTask?.cancel()
            revealTask = nil
            visibleText = target
            return
        }

        if !target.hasPrefix(visibleText) {
            visibleText = ""
        }

        startIfNeeded()
    }

    func cancel() {
        revealTask?.cancel()
        revealTask = nil
    }

    private func startIfNeeded() {
        guard revealTask == nil else { return }

        revealTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let characters = Array(targetText)
                let currentCount = visibleText.count

                guard currentCount < characters.count else {
                    visibleText = targetText
                    revealTask = nil
                    return
                }

                var nextCount = currentCount + 1
                while nextCount < characters.count,
                      !characters[nextCount].isWhitespace {
                    nextCount += 1
                }
                if nextCount < characters.count {
                    nextCount += 1
                }

                visibleText = String(characters.prefix(nextCount))

                // Keep the reveal fast, but long enough to be perceptible on
                // short completed answers as well as live streamed content.
                let isBehind = characters.count - nextCount > 180
                let delay: UInt64 = isBehind ? 9_000_000 : 28_000_000
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    revealTask = nil
                    return
                }
            }

            revealTask = nil
        }
    }
}
