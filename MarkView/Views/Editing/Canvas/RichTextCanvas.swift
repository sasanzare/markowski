import AppKit
import SwiftUI

/// The WYSIWYG canvas: a real `NSTextView` on TextKit 2, editing the document
/// directly.
///
/// Typing goes straight into `NSTextStorage` — the layout manager relays only
/// the affected range, and no part of the UI is rebuilt. The document model is
/// read back out of the storage when something needs it (saving, the
/// assistant), rather than being re-derived on every keystroke.
struct RichTextCanvas: NSViewRepresentable {
    /// The Markdown on disk. Written back only when the user actually changes
    /// something, and re-projected only when it changes underneath us.
    @Binding var markdown: String

    var theme: DocumentTheme = .standard
    var isEditable: Bool = true
    var onSelectionChange: ((String?) -> Void)?
    /// The selection bar's "Ask" button, forwarded to the assistant sidebar.
    var onAssistantRequest: ((String) -> Void)?
    /// Where the document lives, so relative image paths resolve.
    var documentDirectory: URL?
    /// Where the formatting panel learns which table the caret is in.
    var tableBridge: TableSelectionBridge?
    /// Hands the text view to whoever needs to drive it — navigation to a
    /// cited location, for one.
    var onTextViewReady: ((NSTextView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        // TextKit 2. `NSTextView(usingTextLayoutManager:)` is what opts in;
        // the older path silently falls back to TextKit 1.
        let textView = CanvasTextView(usingTextLayoutManager: true)
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = true
        textView.textContainerInset = NSSize(width: 28, height: 34)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand
        ]

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        context.coordinator.textView = textView
        textView.onAssistantRequest = { [weak coordinator = context.coordinator] text in
            coordinator?.parent.onAssistantRequest?(text)
        }

        context.coordinator.project(markdown: markdown, theme: theme)
        onTextViewReady?(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? CanvasTextView else { return }

        textView.isEditable = isEditable

        // Re-project only when the document changed *outside* the canvas.
        // Re-projecting on our own edit would reset the caret on every
        // keystroke — the exact churn this architecture exists to remove.
        if context.coordinator.lastKnownMarkdown != markdown {
            context.coordinator.project(markdown: markdown, theme: theme)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextCanvas
        weak var textView: CanvasTextView?

        /// The Markdown this canvas last agreed with, so an echo of our own
        /// write is not mistaken for an external change.
        var lastKnownMarkdown: String?
        private var isProjecting = false

        init(_ parent: RichTextCanvas) {
            self.parent = parent
        }

        func project(markdown: String, theme: DocumentTheme) {
            guard let textView, let storage = textView.textStorage else { return }

            isProjecting = true
            defer { isProjecting = false }

            RichTextRenderer.imageBaseURL = parent.documentDirectory
            let document = MarkdownDocumentParser.parse(markdown)
            let attributed = RichTextRenderer.attributedString(for: document, theme: theme)

            let selection = textView.selectedRange()
            let scrollView = textView.enclosingScrollView
            let savedScrollOrigin = scrollView?.contentView.bounds.origin

            storage.setAttributedString(attributed)
            textView.theme = theme

            let safeLocation = min(selection.location, storage.length)
            let safeLength = min(selection.length, storage.length - safeLocation)
            textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))

            wireTableAttachments(in: storage)
            lastKnownMarkdown = markdown

            // Replacing the storage resets the scroll to the top. The user was
            // reading somewhere; put them back there.
            if let scrollView, let savedScrollOrigin, savedScrollOrigin.y > 0 {
                if let layoutManager = textView.textLayoutManager {
                    layoutManager.ensureLayout(for: layoutManager.documentRange)
                }
                textView.layoutSubtreeIfNeeded()
                let maximumOffset = max(0, textView.frame.height - scrollView.contentSize.height)
                let target = NSPoint(x: savedScrollOrigin.x, y: min(savedScrollOrigin.y, maximumOffset))
                scrollView.contentView.scroll(to: target)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }

        /// Edits inside a table happen in an attachment's own view, which the
        /// outer text view never hears about — so each attachment reports
        /// directly.
        private func wireTableAttachments(in storage: NSTextStorage) {
            storage.enumerateAttribute(.attachment, in: storage.fullRange, options: []) { value, _, _ in
                guard let attachment = value as? TableAttachment else { return }
                attachment.onChange = { [weak self] _, _ in
                    self?.commitFromStorage()
                }
                attachment.onSelectionChange = { [weak self] grid, context in
                    guard let bridge = self?.parent.tableBridge else { return }
                    if let context {
                        bridge.focus(grid, context: context)
                    } else {
                        bridge.release(grid)
                    }
                }
            }
        }

        /// Reads the storage back into Markdown and publishes it.
        func commitFromStorage() {
            guard !isProjecting, let textView, let storage = textView.textStorage else { return }

            let document = RichTextReader.document(from: storage)
            let markdown = MarkdownDocumentSerializer.serialize(document)

            guard markdown != lastKnownMarkdown else { return }
            lastKnownMarkdown = markdown
            parent.markdown = markdown
        }

        func textDidChange(_ notification: Notification) {
            // A structural edit can introduce fresh table attachments; they
            // report through closures, so they must be (re)wired. Idempotent.
            if let storage = textView?.textStorage {
                wireTableAttachments(in: storage)
            }
            commitFromStorage()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()
            guard range.length > 0 else { return }

            let selected = (textView.string as NSString).substring(with: range)
            guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            parent.onSelectionChange?(selected)
        }

        /// Keeps generated chrome — a bullet, a checkbox, a cell separator —
        /// from being edited into nonsense.
        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            // The canvas's own block operations rewrite chrome deliberately —
            // the guard below exists to stop *typing* into it.
            if (textView as? CanvasTextView)?.isPerformingStructuralEdit == true { return true }

            guard let storage = textView.textStorage, affectedCharRange.length > 0 else { return true }
            guard affectedCharRange.location < storage.length else { return true }

            var touchesDecoration = false
            storage.enumerateAttribute(
                .mvDecoration,
                in: NSRange(
                    location: affectedCharRange.location,
                    length: min(affectedCharRange.length, storage.length - affectedCharRange.location)
                ),
                options: []
            ) { value, _, stop in
                if value != nil {
                    touchesDecoration = true
                    stop.pointee = true
                }
            }
            return !touchesDecoration
        }
    }
}

/// The text view itself. Subclassed for the behaviours a document editor needs
/// and a plain text view has no reason to know about.
final class CanvasTextView: NSTextView {
    var theme: DocumentTheme = .standard

    /// True while a block operation is rewriting structure on purpose, so the
    /// delegate's chrome guard lets the change through (it exists to stop
    /// *typing* into generated markers, not the editor's own commands).
    var isPerformingStructuralEdit = false

    /// Asks the assistant about the selected text.
    var onAssistantRequest: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    /// A document canvas should be comfortable to read: cap the measure and
    /// centre it, the way a page does, instead of running text to the window
    /// edge.
    private let maximumLineWidth: CGFloat = 760

    override func layout() {
        super.layout()
        applyReadableMeasure()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applyReadableMeasure()
    }

    private func applyReadableMeasure() {
        guard let container = textContainer, let scrollView = enclosingScrollView else { return }
        let available = scrollView.contentSize.width
        let width = min(maximumLineWidth, max(320, available - 56))
        let inset = max(28, (available - width) / 2)

        if abs(textContainerInset.width - inset) > 0.5 {
            textContainerInset = NSSize(width: inset, height: textContainerInset.height)
        }
        let target = max(0, available - inset * 2)
        if abs(container.size.width - target) > 0.5 {
            container.size = NSSize(width: target, height: container.size.height)
        }
    }

    /// Word-style autoformat: a Markdown prefix typed at the start of a body
    /// paragraph becomes the real structure the moment the space lands —
    /// `# ` a heading, `- ` a bullet, `1. ` a numbered item, `> ` a quote,
    /// `[] ` a checkbox. ⌘Z gives the literal characters back.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)

        let typed = (string as? String) ?? (string as? NSAttributedString)?.string
        if typed == " " { applyTypedShortcutIfNeeded() }
    }

    private func applyTypedShortcutIfNeeded() {
        guard let storage = textStorage else { return }
        let selection = selectedRange()
        guard selection.length == 0, selection.location > 0 else { return }

        let text = string as NSString
        let paragraph = text.paragraphRange(for: NSRange(location: selection.location, length: 0))
        let prefixRange = NSRange(location: paragraph.location, length: selection.location - paragraph.location)
        guard prefixRange.length >= 2, prefixRange.length <= 8 else { return }

        // Only body paragraphs convert — typing "- " inside a code block is
        // content, not a command.
        if paragraph.location < storage.length,
           let descriptor = storage.attribute(.mvParagraph, at: paragraph.location, effectiveRange: nil) as? ParagraphDescriptor {
            guard case .paragraph = descriptor.role else { return }
        }

        let prefix = text.substring(with: prefixRange)
        let convert: (() -> Void)?
        switch prefix {
        case "- ", "* ", "+ ":
            convert = { self.toggleList(ordered: false, checkbox: false) }
        case "[] ", "[ ] ":
            convert = { self.toggleList(ordered: false, checkbox: true) }
        case "> ":
            convert = { self.toggleQuote() }
        default:
            if prefix.hasSuffix(" "), prefix.dropLast().allSatisfy({ $0 == "#" }), (1...6).contains(prefix.count - 1) {
                let level = prefix.count - 1
                convert = { self.setHeadingLevel(level) }
            } else if prefix.count >= 3, prefix.hasSuffix(". ") || prefix.hasSuffix(") "),
                      prefix.dropLast(2).allSatisfy({ $0.isNumber }) {
                convert = { self.toggleList(ordered: true, checkbox: false) }
            } else {
                convert = nil
            }
        }
        guard let convert else { return }

        isPerformingStructuralEdit = true
        guard shouldChangeText(in: prefixRange, replacementString: "") else {
            isPerformingStructuralEdit = false
            return
        }
        storage.beginEditing()
        storage.replaceCharacters(in: prefixRange, with: "")
        storage.endEditing()
        isPerformingStructuralEdit = false
        didChangeText()
        convert()
    }

    /// Return in a list continues the list; Return on an empty item ends it.
    /// A line holding only ``` becomes a code block instead of text.
    override func insertNewline(_ sender: Any?) {
        if convertFenceLineIfNeeded() { return }

        guard let storage = textStorage,
              let descriptor = storage.paragraphDescriptor(at: max(0, selectedRange().location - 1)),
              case .listItem = descriptor.role else {
            super.insertNewline(sender)
            return
        }

        // An empty item means "I'm done with this list".
        let paragraph = currentParagraphText()
        let content = paragraph.replacingOccurrences(of: "\t", with: "").trimmingCharacters(in: .whitespaces)
        let markerless = content.trimmingCharacters(in: CharacterSet(charactersIn: "•☐☑0123456789."))

        if markerless.isEmpty {
            super.insertNewline(sender)
            return
        }
        super.insertNewline(sender)
    }

    private func currentParagraphText() -> String {
        let text = string as NSString
        let range = text.paragraphRange(for: selectedRange())
        return text.substring(with: range)
    }

    /// ⌘B and ⌘I arrive as font changes. The semantic style has to be updated
    /// alongside the font, or the change would look right and save as nothing.
    override func changeFont(_ sender: Any?) {
        let range = selectedRange()
        super.changeFont(sender)
        syncInlineStyle(in: range)
    }

    func toggleInlineStyle(_ style: InlineStyle) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return }

        // Chrome (a bullet, a checkbox) is skipped rather than refused:
        // bolding a whole list item should bold its text, not fail because
        // the selection happens to include the marker.
        var targets: [NSRange] = []
        storage.enumerateAttribute(.mvDecoration, in: range, options: []) { value, subrange, _ in
            if value == nil, subrange.length > 0 { targets.append(subrange) }
        }
        guard !targets.isEmpty else { return }
        guard shouldChangeText(inRanges: targets.map { NSValue(range: $0) }, replacementStrings: nil) else { return }

        // Applying to a mixed selection turns it all on, which is what every
        // editor does and what people expect.
        var allHaveStyle = true
        for target in targets {
            storage.enumerateAttribute(.mvInlineStyle, in: target, options: []) { value, _, stop in
                let current = InlineStyle(rawValue: (value as? Int) ?? 0)
                if !current.contains(style) {
                    allHaveStyle = false
                    stop.pointee = true
                }
            }
            if !allHaveStyle { break }
        }

        storage.beginEditing()
        for target in targets {
            storage.enumerateAttributes(in: target, options: []) { attributes, subrange, _ in
                var current = InlineStyle(rawValue: (attributes[.mvInlineStyle] as? Int) ?? 0)
                if allHaveStyle { current.subtract(style) } else { current.formUnion(style) }
                storage.addAttribute(.mvInlineStyle, value: current.rawValue, range: subrange)

                if style.contains(.code) {
                    if allHaveStyle {
                        // Back to the paragraph's own typography, keeping any
                        // bold or italic the run still carries.
                        let role = (attributes[.mvParagraph] as? ParagraphDescriptor)?.role ?? .paragraph
                        let text = (storage.string as NSString).substring(with: subrange)
                        var font = RichTextRenderer.baseFont(for: role, theme: theme, text: text)
                        let manager = NSFontManager.shared
                        if current.contains(.bold) { font = manager.convert(font, toHaveTrait: .boldFontMask) }
                        if current.contains(.italic) { font = manager.convert(font, toHaveTrait: .italicFontMask) }
                        storage.addAttribute(.font, value: font, range: subrange)
                    } else {
                        storage.addAttribute(
                            .font,
                            value: NSFont.monospacedSystemFont(ofSize: theme.codeSize, weight: .regular),
                            range: subrange
                        )
                    }
                } else if var font = attributes[.font] as? NSFont {
                    let manager = NSFontManager.shared
                    if style.contains(.bold) {
                        font = allHaveStyle
                            ? manager.convert(font, toNotHaveTrait: .boldFontMask)
                            : manager.convert(font, toHaveTrait: .boldFontMask)
                    }
                    if style.contains(.italic) {
                        font = allHaveStyle
                            ? manager.convert(font, toNotHaveTrait: .italicFontMask)
                            : manager.convert(font, toHaveTrait: .italicFontMask)
                    }
                    storage.addAttribute(.font, value: font, range: subrange)
                }
                if style.contains(.strikethrough) {
                    storage.addAttribute(
                        .strikethroughStyle,
                        value: allHaveStyle ? 0 : NSUnderlineStyle.single.rawValue,
                        range: subrange
                    )
                }
                // The background reflects the run's *resulting* style, so
                // highlight and code can coexist and removing one keeps the
                // other's colour.
                if !style.intersection([.code, .highlight]).isEmpty {
                    if current.contains(.highlight) {
                        storage.addAttribute(
                            .backgroundColor,
                            value: NSColor.systemYellow.withAlphaComponent(0.32),
                            range: subrange
                        )
                    } else if current.contains(.code) {
                        storage.addAttribute(
                            .backgroundColor,
                            value: NSColor.quaternaryLabelColor.withAlphaComponent(0.14),
                            range: subrange
                        )
                    } else {
                        storage.removeAttribute(.backgroundColor, range: subrange)
                    }
                }
            }
        }
        storage.endEditing()

        didChangeText()
    }

    /// Converts the paragraph under the caret between body text and heading
    /// levels — in place, so the selection and the scroll never move. Level 0
    /// means body text.
    ///
    /// Returns `false` for paragraphs whose structure isn't a heading's to
    /// take: list items, code lines, quotes, tables.
    @discardableResult
    func setHeadingLevel(_ level: Int) -> Bool {
        guard let storage = textStorage else { return false }
        let text = string as NSString
        let selection = selectedRange()
        let paragraphRange = text.paragraphRange(for: selection)

        var contentRange = paragraphRange
        while contentRange.length > 0, text.character(at: contentRange.upperBound - 1) == 0x0A {
            contentRange.length -= 1
        }

        let descriptor = contentRange.length > 0
            ? storage.attribute(.mvParagraph, at: contentRange.location, effectiveRange: nil) as? ParagraphDescriptor
            : nil

        let role = descriptor?.role ?? .paragraph
        switch role {
        case .paragraph, .heading:
            break
        default:
            return false
        }

        let blockID = descriptor?.blockID ?? UUID()
        let newRole: ParagraphRole = level <= 0 ? .paragraph : .heading(level: level)
        guard role != newRole else { return true }

        // An empty paragraph has no characters to restyle; arm the typing
        // attributes so the next character arrives as the chosen style.
        guard contentRange.length > 0 else {
            armTypingAttributes(for: ParagraphDescriptor(blockID: blockID, role: newRole))
            return true
        }

        let inline = RichTextReader.inlineText(from: storage.attributedSubstring(from: contentRange))
        let content: BlockContent = level <= 0 ? .paragraph(inline) : .heading(level: level, content: inline)
        let rendered = RichTextRenderer.attributedString(for: RichBlock(id: blockID, content: content), theme: theme)

        guard shouldChangeText(in: contentRange, replacementString: rendered.string) else { return false }
        storage.beginEditing()
        storage.replaceCharacters(in: contentRange, with: rendered)
        storage.endEditing()
        didChangeText()

        let upperBound = contentRange.location + rendered.length
        let caret = min(selection.location, upperBound)
        let length = min(selection.length, upperBound - caret)
        setSelectedRange(NSRange(location: caret, length: length))
        scrollRangeToVisible(selectedRange())
        return true
    }

    /// The shortcuts a writing surface owes its users: ⌘B bold, ⌘I italic,
    /// ⌘E inline code, ⇧⌘X strikethrough. With no selection they fall through
    /// to the system behaviour rather than silently doing nothing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isEditable, flags.contains(.command), !flags.contains(.option), !flags.contains(.control),
              selectedRange().length > 0,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch (key, flags.contains(.shift)) {
        case ("b", false):
            toggleInlineStyle(.bold)
            return true
        case ("i", false):
            toggleInlineStyle(.italic)
            return true
        case ("e", false):
            toggleInlineStyle(.code)
            return true
        case ("x", true):
            toggleInlineStyle(.strikethrough)
            return true
        case ("k", false):
            promptForLink()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    /// Sets the typing attributes for an empty paragraph of the given role.
    /// The `.mvInlineStyle: 0` matters: without it, a heading's bold *font*
    /// would be read back as bold *content* and save as `**text**`.
    private func armTypingAttributes(for descriptor: ParagraphDescriptor) {
        let font: NSFont
        if case .code = descriptor.role {
            font = .monospacedSystemFont(ofSize: theme.codeSize, weight: .regular)
        } else {
            font = RichTextRenderer.baseFont(for: descriptor.role, theme: theme, text: "")
        }
        typingAttributes = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: RichTextRenderer.paragraphStyle(for: descriptor.role, theme: theme, isRTL: false),
            .mvParagraph: descriptor,
            .mvInlineStyle: 0
        ]
    }

    /// The caret sitting right after a generated marker inherits the marker's
    /// attributes — typing there would produce more chrome, which the reader
    /// strips and the user loses. Content attributes win instead.
    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)

        // Only once the drag has settled, or the bar would chase the pointer
        // across the screen while the user is still choosing what to select.
        if !stillSelecting { updateSelectionToolbar() }

        guard typingAttributes[.mvDecoration] != nil else { return }
        var attributes = typingAttributes
        attributes[.mvDecoration] = nil
        attributes[.foregroundColor] = NSColor.labelColor
        attributes[.mvInlineStyle] = 0
        typingAttributes = attributes
    }

    // MARK: - The floating selection toolbar

    private var selectionToolbar: SelectionToolbar?

    private func makeSelectionToolbar() -> SelectionToolbar {
        let toolbar = SelectionToolbar()
        toolbar.onStyle = { [weak self] choice in self?.applyBlockStyle(choice) }
        toolbar.onInline = { [weak self] style in
            self?.toggleInlineStyle(style)
            self?.updateSelectionToolbar()
        }
        toolbar.onLink = { [weak self] in self?.promptForLink() }
        toolbar.onAssistant = { [weak self] in
            guard let self else { return }
            let range = self.selectedRange()
            guard range.length > 0 else { return }
            self.onAssistantRequest?((self.string as NSString).substring(with: range))
        }
        addSubview(toolbar)
        selectionToolbar = toolbar
        return toolbar
    }

    /// Shows the bar over the selection, or hides it when there is nothing to
    /// act on. Safe to call as often as the selection changes.
    func updateSelectionToolbar() {
        guard isEditable,
              window != nil,
              selectedRange().length > 0,
              window?.firstResponder === self,
              let anchor = selectionAnchorRect() else {
            selectionToolbar?.isHidden = true
            return
        }

        let toolbar = selectionToolbar ?? makeSelectionToolbar()
        toolbar.isHidden = false
        toolbar.reflect(style: currentBlockStyle, activeInlineStyles: activeInlineStyles)

        toolbar.layoutSubtreeIfNeeded()
        let size = toolbar.fittingSize
        let visible = visibleRect

        // Above the selection by preference, below it when the first line is
        // near the top of the viewport and there is no room.
        var origin = NSPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - size.height - 8
        )
        if origin.y < visible.minY + 4 {
            origin.y = anchor.maxY + 8
        }
        origin.x = min(max(origin.x, visible.minX + 6), visible.maxX - size.width - 6)

        toolbar.frame = NSRect(origin: origin, size: size)
    }

    /// The rect of the first line of the selection, in this view's coordinates.
    private func selectionAnchorRect() -> NSRect? {
        guard let window else { return nil }
        let screenRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        guard screenRect.width.isFinite, screenRect.height.isFinite, screenRect.height > 0 else { return nil }

        let windowRect = window.convertFromScreen(screenRect)
        return convert(windowRect, from: nil)
    }

    /// The inline styles every character of the selection carries, so the bar
    /// can show them as lit.
    private var activeInlineStyles: InlineStyle {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return [] }

        var shared: InlineStyle = [.bold, .italic, .code, .strikethrough, .highlight]
        var sawContent = false
        storage.enumerateAttributes(in: range, options: []) { attributes, _, _ in
            guard attributes[.mvDecoration] == nil else { return }
            sawContent = true
            shared.formIntersection(InlineStyle(rawValue: (attributes[.mvInlineStyle] as? Int) ?? 0))
        }
        return sawContent ? shared : []
    }

    /// What kind of block the selection sits in. `nil` when it spans several
    /// different kinds, where showing any one of them would be a lie.
    var currentBlockStyle: BlockStyleChoice? {
        guard let storage = textStorage, storage.length > 0 else { return .body }
        let text = string as NSString
        let paragraphs = text.paragraphRange(for: selectedRange())

        var found: Set<BlockStyleChoice> = []
        var location = paragraphs.location
        while location < NSMaxRange(paragraphs), location < storage.length {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))

            if contentsEnd > location,
               let descriptor = storage.attribute(.mvParagraph, at: location, effectiveRange: nil) as? ParagraphDescriptor {
                found.insert(Self.style(for: descriptor.role))
            } else {
                found.insert(.body)
            }
            if lineEnd == location { break }
            location = lineEnd
        }
        return found.count == 1 ? found.first : nil
    }

    private static func style(for role: ParagraphRole) -> BlockStyleChoice {
        switch role {
        case .heading(let level):
            switch level {
            case 1: return .heading1
            case 2: return .heading2
            default: return .heading3
            }
        case .listItem(let ordered, _, let checkbox, _, _):
            if checkbox != nil { return .checklist }
            return ordered ? .numberedList : .bulletList
        case .quote: return .quote
        case .code, .raw: return .codeBlock
        default: return .body
        }
    }

    /// Applies a choice from the bar's style menu.
    func applyBlockStyle(_ choice: BlockStyleChoice) {
        // Turning something into what it already is should do nothing, rather
        // than toggle it back off — a menu is not a toggle.
        guard currentBlockStyle != choice else { return }

        switch choice {
        case .body:
            switch currentBlockStyle {
            case .bulletList, .numberedList, .checklist:
                toggleList(
                    ordered: currentBlockStyle == .numberedList,
                    checkbox: currentBlockStyle == .checklist
                )
            case .quote:
                toggleQuote()
            case .codeBlock:
                toggleCodeBlock()
            default:
                setHeadingLevel(0)
            }
        case .heading1: setHeadingLevel(1)
        case .heading2: setHeadingLevel(2)
        case .heading3: setHeadingLevel(3)
        case .bulletList: toggleList(ordered: false, checkbox: false)
        case .numberedList: toggleList(ordered: true, checkbox: false)
        case .checklist: toggleList(ordered: false, checkbox: true)
        case .quote: toggleQuote()
        case .codeBlock: toggleCodeBlock()
        }
        updateSelectionToolbar()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { selectionToolbar?.isHidden = true }
        return resigned
    }

    override func didChangeText() {
        super.didChangeText()
        updateSelectionToolbar()
    }

    // MARK: - Word-like editing behaviours

    /// Tab and Shift-Tab indent and outdent list items instead of inserting a
    /// tab character, the way every outliner and word processor works.
    override func insertTab(_ sender: Any?) {
        if adjustListIndent(by: 1) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if adjustListIndent(by: -1) { return }
        super.insertBacktab(sender)
    }

    private func adjustListIndent(by delta: Int) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        let text = string as NSString
        let paragraphs = text.paragraphRange(for: selectedRange())
        guard paragraphs.location < text.length else { return false }

        isPerformingStructuralEdit = true
        defer { isPerformingStructuralEdit = false }

        var touchedListItem = false
        var changed = false
        guard shouldChangeText(in: paragraphs, replacementString: nil) else { return false }

        storage.beginEditing()
        var location = paragraphs.location
        while location < NSMaxRange(paragraphs) {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let content = NSRange(location: location, length: contentsEnd - location)
            defer { location = lineEnd }

            guard content.length > 0,
                  let descriptor = storage.attribute(.mvParagraph, at: content.location, effectiveRange: nil) as? ParagraphDescriptor,
                  case .listItem(let ordered, let indent, let checkbox, let ordinal, let itemID) = descriptor.role else {
                continue
            }
            touchedListItem = true

            let newIndent = max(0, min(6, indent + delta))
            guard newIndent != indent else { continue }
            changed = true

            let newDescriptor = ParagraphDescriptor(
                blockID: descriptor.blockID,
                role: .listItem(ordered: ordered, indent: newIndent, checkbox: checkbox, ordinal: ordinal, itemID: itemID),
                lineIndex: descriptor.lineIndex
            )
            let isRTL = TextDirection.isRightToLeft(text.substring(with: content))
            storage.addAttribute(.mvParagraph, value: newDescriptor, range: content)
            storage.addAttribute(
                .paragraphStyle,
                value: RichTextRenderer.paragraphStyle(for: newDescriptor.role, theme: theme, isRTL: isRTL),
                range: content
            )
        }
        storage.endEditing()
        if changed { didChangeText() }
        // Swallow Tab whenever the caret is in a list, even at the indent
        // limits — inserting a literal tab there is never what was meant.
        return touchedListItem
    }

    /// A click on a checkbox toggles it, without needing the sidebar.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, let storage = textStorage, storage.length > 0 {
            let point = convert(event.locationInWindow, from: nil)
            let index = characterIndexForInsertion(at: point)
            for candidate in [index, index - 1] where candidate >= 0 && candidate < storage.length {
                let character = (storage.string as NSString).character(at: candidate)
                guard character == 0x2610 || character == 0x2611,
                      storage.attribute(.mvDecoration, at: candidate, effectiveRange: nil) != nil else { continue }
                toggleCheckbox(at: candidate)
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Flips the checkbox glyph *and* the descriptor that gives it meaning, so
    /// the change saves as `[x]` rather than only looking checked.
    func toggleCheckbox(at index: Int) {
        guard let storage = textStorage,
              index >= 0, index < storage.length,
              let descriptor = storage.attribute(.mvParagraph, at: index, effectiveRange: nil) as? ParagraphDescriptor,
              case .listItem(let ordered, let indent, let checkbox, let ordinal, let itemID) = descriptor.role,
              let checked = checkbox else { return }

        let newDescriptor = ParagraphDescriptor(
            blockID: descriptor.blockID,
            role: .listItem(ordered: ordered, indent: indent, checkbox: !checked, ordinal: ordinal, itemID: itemID),
            lineIndex: descriptor.lineIndex
        )
        let text = string as NSString
        var paragraph = text.paragraphRange(for: NSRange(location: index, length: 0))
        while paragraph.length > 0, text.character(at: NSMaxRange(paragraph) - 1) == 0x0A {
            paragraph.length -= 1
        }

        isPerformingStructuralEdit = true
        defer { isPerformingStructuralEdit = false }
        let glyph = checked ? "☐" : "☑"
        guard shouldChangeText(in: NSRange(location: index, length: 1), replacementString: glyph) else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: index, length: 1), with: glyph)
        storage.addAttribute(.mvParagraph, value: newDescriptor, range: paragraph)
        storage.endEditing()
        didChangeText()
    }

    /// A paragraph holding only ``` (plus an optional language) becomes a code
    /// block when Return is pressed on it.
    private func convertFenceLineIfNeeded() -> Bool {
        guard let storage = textStorage else { return false }
        let selection = selectedRange()
        guard selection.length == 0 else { return false }

        let text = string as NSString
        let paragraph = text.paragraphRange(for: selection)
        var content = paragraph
        while content.length > 0, text.character(at: NSMaxRange(content) - 1) == 0x0A {
            content.length -= 1
        }
        guard content.length >= 3, selection.location == NSMaxRange(content) else { return false }

        if content.location < storage.length,
           let descriptor = storage.attribute(.mvParagraph, at: content.location, effectiveRange: nil) as? ParagraphDescriptor {
            guard case .paragraph = descriptor.role else { return false }
        }

        let line = text.substring(with: content)
        guard line.hasPrefix("```") else { return false }
        let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        guard language.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "#" }) else { return false }

        // An empty code block is zero characters, and zero characters can hold
        // no attributes — so consume the fence and arm the typing attributes;
        // the block materialises with the first character typed into it.
        isPerformingStructuralEdit = true
        defer { isPerformingStructuralEdit = false }
        guard shouldChangeText(in: content, replacementString: "") else { return false }
        storage.beginEditing()
        storage.replaceCharacters(in: content, with: "")
        storage.endEditing()
        didChangeText()

        armTypingAttributes(for: ParagraphDescriptor(
            blockID: UUID(),
            role: .code(language: language.isEmpty ? nil : language)
        ))
        return true
    }

    // MARK: - Block-level operations

    private struct BlockParagraph {
        let content: NSRange
        let full: NSRange
        let descriptor: ParagraphDescriptor?
    }

    private var blockParagraphs: [BlockParagraph] {
        let text = string as NSString
        var result: [BlockParagraph] = []
        var location = 0
        while location < text.length {
            var lineEnd = 0
            var contentsEnd = 0
            text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let content = NSRange(location: location, length: contentsEnd - location)
            let descriptor = content.length > 0
                ? textStorage?.attribute(.mvParagraph, at: location, effectiveRange: nil) as? ParagraphDescriptor
                : nil
            result.append(BlockParagraph(
                content: content,
                full: NSRange(location: location, length: lineEnd - location),
                descriptor: descriptor
            ))
            if lineEnd == location { break }
            location = lineEnd
        }
        // The empty paragraph after a trailing Return is real to the user —
        // a block command with the caret there must not grab the line above.
        if text.length == 0 || text.character(at: text.length - 1) == 0x0A {
            let end = NSRange(location: text.length, length: 0)
            result.append(BlockParagraph(content: end, full: end, descriptor: nil))
        }
        return result
    }

    /// The storage range covering every whole block the selection touches.
    /// Multi-paragraph blocks (lists, code, quotes) are taken whole, so a
    /// structural command can never cut one in half.
    func blockRange(for selection: NSRange) -> NSRange {
        let all = blockParagraphs
        guard !all.isEmpty else { return NSRange(location: 0, length: 0) }

        var first = all.firstIndex { NSMaxRange($0.full) > selection.location } ?? all.count - 1
        var last = first
        let upper = NSMaxRange(selection)
        while last + 1 < all.count, all[last + 1].full.location < upper { last += 1 }

        func spansParagraphs(_ role: ParagraphRole?) -> Bool {
            switch role {
            case .listItem, .code, .quote, .raw: return true
            default: return false
            }
        }
        while first > 0,
              let id = all[first].descriptor?.blockID,
              spansParagraphs(all[first].descriptor?.role),
              all[first - 1].descriptor?.blockID == id {
            first -= 1
        }
        while last + 1 < all.count,
              let id = all[last].descriptor?.blockID,
              spansParagraphs(all[last].descriptor?.role),
              all[last + 1].descriptor?.blockID == id {
            last += 1
        }

        let location = all[first].full.location
        return NSRange(location: location, length: NSMaxRange(all[last].content) - location)
    }

    private func blocks(in range: NSRange) -> [RichBlock] {
        guard let storage = textStorage, range.length > 0 else { return [] }
        return RichTextReader.document(from: storage.attributedSubstring(from: range)).blocks
    }

    /// Replaces a storage range with freshly rendered blocks, keeping the
    /// caret in place (and off generated chrome) and registering undo.
    @discardableResult
    func replaceBlocks(in range: NSRange, with blocks: [RichBlock]) -> Bool {
        guard let storage = textStorage, !blocks.isEmpty else { return false }
        let selection = selectedRange()

        let rendered = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 { rendered.append(NSAttributedString(string: RichTextRenderer.paragraphSeparator)) }
            rendered.append(RichTextRenderer.attributedString(for: block, theme: theme))
        }

        isPerformingStructuralEdit = true
        defer { isPerformingStructuralEdit = false }
        guard shouldChangeText(in: range, replacementString: rendered.string) else { return false }
        storage.beginEditing()
        storage.replaceCharacters(in: range, with: rendered)
        storage.endEditing()
        didChangeText()

        let upperBound = range.location + rendered.length
        var caret = min(max(selection.location, range.location), upperBound)
        while caret < upperBound, caret < storage.length,
              storage.attribute(.mvDecoration, at: caret, effectiveRange: nil) != nil {
            caret += 1
        }
        setSelectedRange(NSRange(location: caret, length: 0))
        scrollRangeToVisible(selectedRange())
        return true
    }

    /// Converts the touched blocks to the requested list kind, or back to
    /// paragraphs when they already are exactly that kind.
    @discardableResult
    func toggleList(ordered: Bool, checkbox: Bool) -> Bool {
        let range = blockRange(for: selectedRange())
        let existing = blocks(in: range)
        let style: ListStyle = ordered ? .ordered(start: 1) : .bulleted

        // An empty paragraph (or empty document) starts a fresh list.
        guard !existing.isEmpty else {
            let item = ListItem(content: InlineText(), checkbox: checkbox ? false : nil)
            return replaceBlocks(in: range, with: [RichBlock(content: .list(style: style, items: [item]))])
        }

        func matchesTarget(_ block: RichBlock) -> Bool {
            guard case .list(let existingStyle, let items) = block.content else { return false }
            let sameFamily: Bool
            switch existingStyle {
            case .bulleted: sameFamily = !ordered
            case .ordered: sameFamily = ordered
            }
            guard sameFamily else { return false }
            let hasCheckboxes = items.contains { $0.checkbox != nil }
            return checkbox ? hasCheckboxes : !hasCheckboxes
        }

        var replacement: [RichBlock] = []
        if existing.allSatisfy(matchesTarget) {
            for block in existing {
                guard case .list(_, let items) = block.content else { continue }
                replacement += items.map { RichBlock(content: .paragraph($0.content)) }
            }
        } else {
            var pending: [ListItem] = []
            func flush() {
                guard !pending.isEmpty else { return }
                replacement.append(RichBlock(content: .list(style: style, items: pending)))
                pending = []
            }
            for block in existing {
                switch block.content {
                case .paragraph(let text), .heading(_, let text):
                    pending.append(ListItem(content: text, checkbox: checkbox ? false : nil))
                case .list(_, let items):
                    pending += items.map { item in
                        var updated = item
                        updated.checkbox = checkbox ? (item.checkbox ?? false) : nil
                        return updated
                    }
                default:
                    // Code, tables, and dividers keep their structure.
                    flush()
                    replacement.append(block)
                }
            }
            flush()
        }
        guard !replacement.isEmpty else { return false }
        return replaceBlocks(in: range, with: replacement)
    }

    /// Wraps the touched blocks in a quote, or unwraps them when they already
    /// are one.
    @discardableResult
    func toggleQuote() -> Bool {
        let range = blockRange(for: selectedRange())
        let existing = blocks(in: range)
        guard !existing.isEmpty else {
            return replaceBlocks(in: range, with: [
                RichBlock(content: .quote(blocks: [RichBlock(content: .paragraph(InlineText()))]))
            ])
        }

        let allQuotes = existing.allSatisfy {
            if case .quote = $0.content { return true }
            return false
        }
        let replacement: [RichBlock]
        if allQuotes {
            replacement = existing.flatMap { block -> [RichBlock] in
                guard case .quote(let inner) = block.content else { return [block] }
                return inner.isEmpty ? [RichBlock(content: .paragraph(InlineText()))] : inner
            }
        } else {
            replacement = [RichBlock(content: .quote(blocks: existing))]
        }
        return replaceBlocks(in: range, with: replacement)
    }

    /// Turns the touched blocks into one code block, or a code block back into
    /// prose.
    @discardableResult
    func toggleCodeBlock() -> Bool {
        let range = blockRange(for: selectedRange())
        let existing = blocks(in: range)
        guard !existing.isEmpty else {
            return replaceBlocks(in: range, with: [RichBlock(content: .code(language: nil, text: ""))])
        }

        if existing.count == 1, case .code(_, let text) = existing[0].content {
            let paragraphs = text.components(separatedBy: "\n").map {
                RichBlock(content: .paragraph(InlineText(plain: $0)))
            }
            return replaceBlocks(in: range, with: paragraphs)
        }

        let text = existing.map(\.plainText).joined(separator: "\n")
        return replaceBlocks(in: range, with: [RichBlock(content: .code(language: nil, text: text))])
    }

    private func insertBlocksAfterCurrentBlock(_ blocks: [RichBlock]) {
        guard let storage = textStorage else { return }
        let current = blockRange(for: selectedRange())
        let insertLocation = NSMaxRange(current)

        let rendered = NSMutableAttributedString()
        for block in blocks {
            if storage.length > 0 || rendered.length > 0 {
                rendered.append(NSAttributedString(string: RichTextRenderer.paragraphSeparator))
            }
            rendered.append(RichTextRenderer.attributedString(for: block, theme: theme))
        }

        isPerformingStructuralEdit = true
        defer { isPerformingStructuralEdit = false }
        guard shouldChangeText(in: NSRange(location: insertLocation, length: 0), replacementString: rendered.string) else {
            return
        }
        storage.beginEditing()
        storage.insert(rendered, at: insertLocation)
        storage.endEditing()
        didChangeText()

        setSelectedRange(NSRange(location: min(insertLocation + rendered.length, storage.length), length: 0))
        scrollRangeToVisible(selectedRange())
    }

    /// Inserts a horizontal rule below the current block, with an empty
    /// paragraph after it so typing can continue immediately.
    func insertDivider() {
        insertBlocksAfterCurrentBlock([
            RichBlock(content: .divider),
            RichBlock(content: .paragraph(InlineText()))
        ])
    }

    /// Places image references below the current block.
    ///
    /// The canvas edits a document model rather than Markdown text, so the
    /// reference is parsed into blocks first — pasting the raw `![](…)` in
    /// would put literal syntax on a surface whose whole point is not showing
    /// any.
    func insertImageBlocks(_ markdown: String) {
        let blocks = MarkdownDocumentParser.parse(markdown).blocks
        guard !blocks.isEmpty else { return }
        insertBlocksAfterCurrentBlock(blocks + [RichBlock(content: .paragraph(InlineText()))])
    }

    /// Inserts a fresh table below the current block.
    func insertTable(rows: Int, columns: Int) {
        let width = max(1, columns)
        let header = TableRow(cells: (0..<width).map { TableCell(content: InlineText(plain: "Column \($0 + 1)")) })
        let body = (0..<max(1, rows - 1)).map { _ in
            TableRow(cells: (0..<width).map { _ in TableCell() })
        }
        let table = TableBlock(header: header, rows: body, alignments: Array(repeating: .none, count: width))
        insertBlocksAfterCurrentBlock([RichBlock(content: .table(table))])
    }

    /// Wraps the touched blocks in the HTML direction container Markdown
    /// understands — or unwraps them when they already carry this direction.
    @discardableResult
    func setBlockDirection(rightToLeft: Bool) -> Bool {
        let range = blockRange(for: selectedRange())
        let existing = blocks(in: range)
        guard !existing.isEmpty else { return false }

        let direction: MarkdownFormatter.BlockDirection = rightToLeft ? .rightToLeft : .leftToRight
        if existing.count == 1, case .raw(let text) = existing[0].content,
           let unwrapped = MarkdownFormatter.unwrapDirection(text) {
            if unwrapped.direction == direction {
                let inner = MarkdownDocumentParser.parse(unwrapped.body).blocks
                return replaceBlocks(
                    in: range,
                    with: inner.isEmpty ? [RichBlock(content: .paragraph(InlineText()))] : inner
                )
            }
            let rewrapped = "<div dir=\"\(direction.rawValue)\" markdown=\"1\">\n\(unwrapped.body)\n</div>"
            return replaceBlocks(in: range, with: [RichBlock(content: .raw(rewrapped))])
        }

        let inner = existing.map(MarkdownDocumentSerializer.serialize).joined(separator: "\n\n")
        let wrapped = "<div dir=\"\(direction.rawValue)\" markdown=\"1\">\n\(inner)\n</div>"
        return replaceBlocks(in: range, with: [RichBlock(content: .raw(wrapped))])
    }

    /// Applies a plain-text transform to the selection run by run, keeping
    /// every attribute in place. Generated chrome and attachments are left
    /// alone. This is what the Persian text tools ride on.
    @discardableResult
    func rewriteSelection(_ transform: (String) -> String) -> Bool {
        let selection = selectedRange()
        guard selection.length > 0, let storage = textStorage else { return false }

        var ranges: [NSRange] = []
        var replacements: [String] = []
        let text = storage.string as NSString
        storage.enumerateAttributes(in: selection, options: []) { attributes, subrange, _ in
            guard attributes[.mvDecoration] == nil, attributes[.attachment] == nil else { return }
            let original = text.substring(with: subrange)
            let updated = transform(original)
            guard updated != original else { return }
            ranges.append(subrange)
            replacements.append(updated)
        }
        guard !ranges.isEmpty else { return false }
        guard shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: replacements) else {
            return false
        }

        storage.beginEditing()
        for (range, replacement) in zip(ranges, replacements).reversed() {
            storage.replaceCharacters(in: range, with: replacement)
        }
        storage.endEditing()
        didChangeText()

        let delta = zip(ranges, replacements).reduce(0) { $0 + ($1.1 as NSString).length - $1.0.length }
        setSelectedRange(NSRange(location: selection.location, length: max(0, selection.length + delta)))
        return true
    }

    // MARK: - Links

    /// Whether every character of the selection already carries a link.
    var selectionIsEntirelyLinked: Bool {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return false }
        var allLinked = true
        storage.enumerateAttributes(in: range, options: []) { attributes, _, stop in
            guard attributes[.mvDecoration] == nil else { return }
            if attributes[.link] == nil {
                allLinked = false
                stop.pointee = true
            }
        }
        return allLinked
    }

    /// Links (or, with nil, unlinks) the selection.
    @discardableResult
    func applyLink(_ destination: String?) -> Bool {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else { return false }

        var targets: [NSRange] = []
        storage.enumerateAttribute(.mvDecoration, in: range, options: []) { value, subrange, _ in
            if value == nil, subrange.length > 0 { targets.append(subrange) }
        }
        guard !targets.isEmpty else { return false }
        guard shouldChangeText(inRanges: targets.map { NSValue(range: $0) }, replacementStrings: nil) else {
            return false
        }

        storage.beginEditing()
        for target in targets {
            if let destination {
                storage.addAttribute(.link, value: destination, range: target)
                storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: target)
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: target)
            } else {
                storage.removeAttribute(.link, range: target)
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: target)
                storage.removeAttribute(.underlineStyle, range: target)
            }
        }
        storage.endEditing()
        didChangeText()
        return true
    }

    /// Asks for a URL and links the selection — or unlinks it when it is
    /// already entirely a link. Bound to ⌘K and the sidebar's link button.
    func promptForLink() {
        guard selectedRange().length > 0 else {
            NSSound.beep()
            return
        }
        if selectionIsEntirelyLinked {
            applyLink(nil)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Add Link"
        alert.informativeText = "The selected text will link to this address."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://example.com"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add Link")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let destination = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return }
        applyLink(destination)
    }

    /// Brings the font traits of a range back into agreement with its semantic
    /// style, after the font panel or ⌘B changed them behind our back.
    private func syncInlineStyle(in range: NSRange) {
        guard range.length > 0, let storage = textStorage else { return }

        storage.beginEditing()
        storage.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
            guard let font = attributes[.font] as? NSFont else { return }
            var style = InlineStyle(rawValue: (attributes[.mvInlineStyle] as? Int) ?? 0)

            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { style.insert(.bold) } else { style.remove(.bold) }
            if traits.contains(.italicFontMask) { style.insert(.italic) } else { style.remove(.italic) }

            storage.addAttribute(.mvInlineStyle, value: style.rawValue, range: subrange)
        }
        storage.endEditing()
    }
}
