import SwiftUI
import AppKit

struct SourceView: NSViewRepresentable {
    @Binding var text: String
    let fontSize: CGFloat
    var navigator: DocumentNavigator? = nil
    var onTextSelected: ((String?) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let contentSize = scrollView.contentSize
        let textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height)
        )
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 16, height: 16)

        let lineNumberRuler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = lineNumberRuler
        scrollView.rulersVisible = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.lineNumberRuler = lineNumberRuler
        context.coordinator.lastFontSize = fontSize
        updateTextView(textView, with: text, fontSize: fontSize)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = nsView.documentView as? NSTextView else { return }
        navigator?.sourceTextView = textView
        navigator?.sourceViewReady()

        let fontChanged = context.coordinator.lastFontSize != fontSize
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.string != text || fontChanged {
            updateTextView(textView, with: text, fontSize: fontSize)
        }
        nsView.verticalRulerView?.needsDisplay = true
    }

    private func updateTextView(_ textView: NSTextView, with text: String, fontSize: CGFloat) {
        let selectedRange = textView.selectedRange()
        let attributedText = MarkdownSyntaxHighlighter.attributedString(for: text, fontSize: fontSize)

        if let coordinator = textView.delegate as? Coordinator {
            coordinator.isUpdatingText = true
            coordinator.lastFontSize = fontSize
        }

        textView.string = text
        textView.textStorage?.setAttributedString(attributedText)

        let location = min(max(selectedRange.location, 0), attributedText.length)
        let length = min(max(selectedRange.length, 0), attributedText.length - location)
        textView.setSelectedRange(NSRange(location: location, length: length))
        if let coordinator = textView.delegate as? Coordinator {
            coordinator.isUpdatingText = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceView
        weak var textView: NSTextView?
        weak var lineNumberRuler: LineNumberRulerView?
        var isUpdatingText = false
        var lastFontSize: CGFloat?

        init(_ parent: SourceView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingText, let textView else { return }

            parent.text = textView.string
            rehighlight(textView)
            lineNumberRuler?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdatingText, let textView else {
                lineNumberRuler?.needsDisplay = true
                return
            }

            // Only a real selection is reported. Reporting the collapse too
            // meant that clicking into the chat — or simply moving the caret —
            // discarded the context the user had just picked; the composer
            // owns clearing it, through its own explicit control.
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 {
                let selectedText = (textView.string as NSString).substring(with: selectedRange)
                if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parent.onTextSelected?(selectedText)
                }
            }
            lineNumberRuler?.needsDisplay = true
        }

        private func rehighlight(_ textView: NSTextView) {
            let selectedRange = textView.selectedRange()
            let attributedText = MarkdownSyntaxHighlighter.attributedString(
                for: textView.string,
                fontSize: parent.fontSize
            )

            isUpdatingText = true
            textView.textStorage?.setAttributedString(attributedText)
            let location = min(max(selectedRange.location, 0), attributedText.length)
            let length = min(max(selectedRange.length, 0), attributedText.length - location)
            textView.setSelectedRange(NSRange(location: location, length: length))
            isUpdatingText = false
        }
    }
}

private enum MarkdownSyntaxTheme {
    // These roles intentionally use the same semantic system colors in both
    // appearances, giving the editor a predictable IDE-like visual language
    // while AppKit adapts each color for light and dark mode.
    static let plain = NSColor.textColor
    static let heading = NSColor.systemBlue
    static let punctuation = NSColor.systemPurple
    static let emphasis = NSColor.systemOrange
    static let code = NSColor.systemGreen
    static let link = NSColor.systemTeal
    static let quote = NSColor.secondaryLabelColor
    static let html = NSColor.systemPink
    static let list = NSColor.systemOrange
}

private enum MarkdownSyntaxHighlighter {
    static func attributedString(for text: String, fontSize: CGFloat) -> NSAttributedString {
        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: MarkdownSyntaxTheme.plain
            ]
        )

        guard !text.isEmpty else { return attributedText }

        let headingFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        apply(
            pattern: #"(?m)^\s*#{1,6}(?:[ \t]+|$).*$"#,
            to: attributedText,
            text: text,
            attributes: [
                .font: headingFont,
                .foregroundColor: MarkdownSyntaxTheme.heading
            ]
        )
        apply(
            pattern: #"(?m)^\s*#{1,6}"#,
            to: attributedText,
            text: text,
            attributes: [.foregroundColor: MarkdownSyntaxTheme.punctuation]
        )

        apply(
            pattern: #"(?m)^\s*>+.*$"#,
            to: attributedText,
            text: text,
            attributes: [
                .font: italicFont,
                .foregroundColor: MarkdownSyntaxTheme.quote
            ]
        )
        apply(
            pattern: #"(?m)^\s*>+"#,
            to: attributedText,
            text: text,
            attributes: [.foregroundColor: MarkdownSyntaxTheme.punctuation]
        )

        apply(
            pattern: #"(?m)^\s*(?:[-+*]|\d+[.)])(?:[ \t]+|$)"#,
            to: attributedText,
            text: text,
            attributes: [.foregroundColor: MarkdownSyntaxTheme.list]
        )
        apply(
            pattern: #"(?m)^\s*(?:[-+*]|\d+[.)])[ \t]+\[[ xX]\]"#,
            to: attributedText,
            text: text,
            attributes: [.foregroundColor: MarkdownSyntaxTheme.punctuation]
        )
        apply(
            pattern: #"(?m)^\s*(?:---+|\*\*\*+|___+)[ \t]*$"#,
            to: attributedText,
            text: text,
            attributes: [.foregroundColor: MarkdownSyntaxTheme.punctuation]
        )

        apply(
            pattern: #"`[^`\n]+`"#,
            to: attributedText,
            text: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: MarkdownSyntaxTheme.code
            ]
        )
        apply(
            pattern: #"\*\*[^\n]+?\*\*|__[^\n]+?__"#,
            to: attributedText,
            text: text,
            attributes: [
                .font: boldFont,
                .foregroundColor: MarkdownSyntaxTheme.emphasis
            ]
        )
        apply(
            pattern: #"(?<!\*)\*[^*\n]+\*(?!\*)|(?<!_)_[^_\n]+_(?!_)"#,
            to: attributedText,
            text: text,
            attributes: [
                .font: italicFont,
                .foregroundColor: MarkdownSyntaxTheme.emphasis
            ]
        )

        apply(
            pattern: #"\[[^\]\n]+\]\([^\)\n]+\)"#,
            to: attributedText,
            text: text,
            attributes: [.foregroundColor: MarkdownSyntaxTheme.link]
        )
        apply(
            pattern: #"https?://[^\s)>]+"#,
            to: attributedText,
            text: text,
            attributes: [.foregroundColor: MarkdownSyntaxTheme.link]
        )
        apply(
            pattern: #"</?[A-Za-z][^>\n]*>"#,
            to: attributedText,
            text: text,
            attributes: [.foregroundColor: MarkdownSyntaxTheme.html]
        )

        applyCodeBlocks(in: attributedText, text: text, font: baseFont)

        // Markdown delimiters remain visually distinct even when their content has
        // a semantic color, which makes the source easier to scan like an IDE.
        apply(
            pattern: #"[`*_~]+"#,
            to: attributedText,
            text: text,
            attributes: [.foregroundColor: MarkdownSyntaxTheme.punctuation]
        )

        return attributedText
    }

    private static func applyCodeBlocks(
        in attributedText: NSMutableAttributedString,
        text: String,
        font: NSFont
    ) {
        let nsText = text as NSString
        var cursor = 0
        var codeBlockStart: Int?
        var fence: String?

        while cursor < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: cursor, length: 0))
            let line = nsText.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lineStart = lineRange.location
            let lineEnd = NSMaxRange(lineRange)

            if let currentFence = fence {
                if trimmed.hasPrefix(currentFence) {
                    if let codeBlockStart {
                        let blockRange = NSRange(location: codeBlockStart, length: lineEnd - codeBlockStart)
                        attributedText.addAttributes([
                            .font: font,
                            .foregroundColor: MarkdownSyntaxTheme.code
                        ], range: blockRange)
                    }
                    codeBlockStart = nil
                    fence = nil
                }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                codeBlockStart = lineStart
                fence = String(trimmed.prefix(3))
            }

            cursor = max(lineEnd, cursor + 1)
        }

        if let codeBlockStart {
            let blockRange = NSRange(location: codeBlockStart, length: nsText.length - codeBlockStart)
            attributedText.addAttributes([
                .font: font,
                .foregroundColor: MarkdownSyntaxTheme.code
            ], range: blockRange)
        }
    }

    private static func apply(
        pattern: String,
        to attributedText: NSMutableAttributedString,
        text: String,
        attributes: [NSAttributedString.Key: Any],
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let range = NSRange(location: 0, length: (text as NSString).length)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, match.range.location != NSNotFound else { return }
            attributedText.addAttributes(attributes, range: match.range)
        }
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 44
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        NSColor.separatorColor.withAlphaComponent(0.1).set()
        rect.fill()

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let string = textView.string as NSString
        var lineNumber = 1

        string.enumerateSubstrings(in: NSRange(location: 0, length: characterRange.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            lineNumber += 1
        }

        let font = NSFont.monospacedSystemFont(ofSize: (textView.font?.pointSize ?? 13) * 0.85, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        var selectedLineNumber = -1
        let selectedRange = textView.selectedRange()
        if selectedRange.location != NSNotFound && selectedRange.location <= string.length {
            var count = 1
            string.enumerateSubstrings(in: NSRange(location: 0, length: selectedRange.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
                count += 1
            }
            selectedLineNumber = count
        }

        string.enumerateSubstrings(in: characterRange, options: [.byLines, .substringNotRequired]) { _, substringRange, _, _ in
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: substringRange.location)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let label = "\(lineNumber)"
            let size = label.size(withAttributes: attributes)
            let y = lineRect.minY + textView.textContainerInset.height - visibleRect.minY + ((lineRect.height - size.height) / 2)
            let x = self.ruleThickness - size.width - 8

            let currentAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: lineNumber == selectedLineNumber ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
            label.draw(at: NSPoint(x: x, y: y), withAttributes: currentAttrs)
            lineNumber += 1
        }
    }
}
