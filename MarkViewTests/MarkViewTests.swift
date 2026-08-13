import XCTest
import SwiftUI
import AppKit
import UniformTypeIdentifiers
@testable import MarkView

final class MarkViewTests: XCTestCase {

    func testPerModelPolicyCapabilities() {
        XCTAssertTrue(AIModelCatalog.supportsReasoningEffort(
            AIModel(id: "o4-mini-2025-04-16", displayName: "o4-mini", provider: .openAI)
        ))
        XCTAssertTrue(AIModelCatalog.supportsReasoningEffort(
            AIModel(id: "gpt-5.2", displayName: "GPT-5.2", provider: .openAI)
        ))
        XCTAssertFalse(AIModelCatalog.supportsReasoningEffort(
            AIModel(id: "gpt-4.1", displayName: "GPT-4.1", provider: .openAI)
        ))
        XCTAssertFalse(AIModelCatalog.isUsableTextModel("nano-banana-pro-preview"))
        XCTAssertFalse(AIModelCatalog.isUsableTextModel("lyria-3-pro-preview"))
    }

    func testTokenResetPeriodMigratesNeverToManual() throws {
        let oldValue = try JSONDecoder().decode(AITokenResetPeriod.self, from: Data("\"Never\"".utf8))
        XCTAssertEqual(oldValue, .manual)
        XCTAssertEqual(AITokenResetPeriod.manual.detail, "Only when you press Reset now")
        XCTAssertEqual(AITokenResetPeriod.daily.detail, "Automatically at local midnight")
    }

    func testPreviewRendererIncludesLocalSyntaxHighlighting() throws {
        let htmlURL = try XCTUnwrap(Bundle.main.url(forResource: "renderer", withExtension: "html"))
        let cssURL = try XCTUnwrap(Bundle.main.url(forResource: "renderer", withExtension: "css"))
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        let css = try String(contentsOf: cssURL, encoding: .utf8)

        XCTAssertTrue(html.contains("highlightCodeBlocks(container)"))
        XCTAssertTrue(html.contains("rust: new Set"))
        XCTAssertTrue(css.contains(".syntax-keyword"))
        XCTAssertTrue(css.contains("pre[data-language]::before"))
    }

    func testDocumentReadableContentTypes() {
        let types = MarkViewDocument.readableContentTypes
        XCTAssertTrue(types.contains(.markdownDocument))
        XCTAssertTrue(types.contains(.plainText))
        XCTAssertTrue(types.contains(UTType(exportedAs: "org.mermaid.diagram")))
    }

    func testDocumentMetadataCalculation() {
        let sampleText = """
        # Hello World
        This is a test document with multiple words.
        Third line of text.
        """
        
        let metadata = DocumentLoader.getMetadata(for: nil, text: sampleText)
        
        XCTAssertEqual(metadata.lineCount, 3)
        XCTAssertEqual(metadata.characterCount, sampleText.count)
        XCTAssertGreaterThan(metadata.wordCount, 5)
        XCTAssertEqual(metadata.fileExtension, "md")
    }

    func testKeychainService() {
        let testAccount = "test_acc_\(UUID().uuidString)"
        let testKey = "sk-test-123456"

        do {
            try KeychainService.shared.saveKey(testKey, forAccount: testAccount)
            let retrieved = KeychainService.shared.getKey(forAccount: testAccount)
            XCTAssertEqual(retrieved, testKey)

            try KeychainService.shared.deleteKey(forAccount: testAccount)
            let afterDelete = KeychainService.shared.getKey(forAccount: testAccount)
            XCTAssertNil(afterDelete)
        } catch {
            XCTFail("Keychain operation failed: \(error)")
        }
    }

    func testDiffEngine() {
        let orig = "Line 1\nLine 2\nLine 3"
        let mod = "Line 1\nLine 2 Modified\nLine 3\nLine 4"

        let summary = DiffEngine.computeDiff(original: orig, modified: mod)
        XCTAssertGreaterThan(summary.additions, 0)
        XCTAssertGreaterThan(summary.deletions, 0)
    }

    func testDocumentSafetyServiceHashAndConflict() {
        let text1 = "Hello World"
        let hash1 = DocumentSafetyService.computeHash(text: text1)
        let hash2 = DocumentSafetyService.computeHash(text: "Hello World")
        let hash3 = DocumentSafetyService.computeHash(text: "Hello World!")

        XCTAssertEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
    }

    func testMermaidValidation() {
        let validGraph = """
        graph TD
            A[Start] --> B(Process)
        """
        let (isValid1, err1) = DocumentSafetyService.validateMermaidSyntax(content: validGraph)
        XCTAssertTrue(isValid1)
        XCTAssertNil(err1)

        let invalidGraph = "InvalidSyntaxWithoutHeader"
        let (isValid2, err2) = DocumentSafetyService.validateMermaidSyntax(content: invalidGraph)
        XCTAssertFalse(isValid2)
        XCTAssertNotNil(err2)
    }

    func testMockAIProvider() async {
        let mock = MockAIProvider()
        do {
            let models = try await mock.fetchModels(apiKey: "dummy")
            XCTAssertFalse(models.isEmpty)

            let isConnected = try await mock.testConnection(apiKey: "dummy")
            XCTAssertTrue(isConnected)
        } catch {
            XCTFail("Mock AI Provider failed: \(error)")
        }
    }

    func testAIModelCatalog() {
        XCTAssertEqual(
            AIModelCatalog.geminiModels.map(\.id),
            ["gemini-pro-latest", "gemini-flash-latest", "gemini-flash-lite-latest"]
        )
        XCTAssertEqual(AIModelCatalog.geminiModels[0].inspectorDisplayName, "Gemini Pro")
        XCTAssertEqual(AIModelCatalog.geminiModels[2].inspectorDisplayName, "Gemini Flash Lite")

        XCTAssertTrue(AIModelCatalog.isTextOnlyOpenAIModel("gpt-4.1-mini"))
        XCTAssertTrue(AIModelCatalog.isTextOnlyOpenAIModel("o3-mini"))
        XCTAssertFalse(AIModelCatalog.isTextOnlyOpenAIModel("gpt-4o-audio-preview"))
        XCTAssertFalse(AIModelCatalog.isTextOnlyOpenAIModel("gpt-4o-realtime-preview"))
        XCTAssertFalse(AIModelCatalog.isTextOnlyOpenAIModel("text-embedding-3-small"))
    }

    func testDocumentIndexAndLocationResolution() {
        let sampleMarkdown = """
        # Introduction
        This is paragraph one.

        # Features
        Here we discuss features in detail.
        """

        let index = DocumentIndex()
        index.buildIndex(from: sampleMarkdown)

        XCTAssertEqual(index.headings.count, 2)
        XCTAssertEqual(index.headings[0], "Introduction")
        XCTAssertEqual(index.headings[1], "Features")

        let location = DocumentLocation(heading: "Features", quote: nil, startLine: nil, endLine: nil, blockId: nil)
        let resolved = index.resolveLocation(location)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.headingTitle, "Features")
    }

    // MARK: - AI assistant

    /// The local shortcut used to fire on any prompt containing "find",
    /// "mention", or "talk about", so real requests never reached the model.
    @MainActor
    func testLocalSearchTermOnlyMatchesLookups() {
        XCTAssertEqual(AIService.localSearchTerm(from: "Where do I mention Kubernetes?"), "Kubernetes")
        XCTAssertEqual(AIService.localSearchTerm(from: "Where is the deadline?"), "deadline")
        XCTAssertEqual(AIService.localSearchTerm(from: "Where does it talk about caching"), "caching")

        XCTAssertNil(AIService.localSearchTerm(from: "Find all the typos and fix them"))
        XCTAssertNil(AIService.localSearchTerm(from: "Summarize the section that mentions Docker"))
        XCTAssertNil(AIService.localSearchTerm(from: "Where should I add the install steps?"))
        XCTAssertNil(AIService.localSearchTerm(from: "Improve writing"))
        XCTAssertNil(AIService.localSearchTerm(from: "Where is it?"))
    }

    @MainActor
    func testExtractPartialContentCoversEditSummaries() {
        let chat = "{\"type\": \"chat_response\", \"content\": \"Hello **world**"
        XCTAssertEqual(AIService.extractPartialContent(from: chat), "Hello **world**")

        // A document_edit has no "content" — its prose lives in "summary", and
        // the sidebar showed nothing at all for rewrites without this.
        let edit = "{\"type\": \"document_edit\", \"summary\": \"Fixed two typos\", \"updated_document\": \"# Ti"
        XCTAssertEqual(AIService.extractPartialContent(from: edit), "Fixed two typos")

        XCTAssertEqual(AIService.extractPartialContent(from: "{\"type\": \"document_edit\""), "")
    }

    @MainActor
    func testStripCodeFence() {
        XCTAssertEqual(AIService.stripCodeFence(from: "```json\n{\"a\": 1}\n```"), "{\"a\": 1}")
        XCTAssertEqual(AIService.stripCodeFence(from: "{\"a\": 1}"), "{\"a\": 1}")
    }

    func testDiffEnginePreservesAlignmentAfterPrefixTrimming() {
        let original = (1...200).map { "Line \($0)" }.joined(separator: "\n")
        let modified = original.replacingOccurrences(of: "Line 100", with: "Line 100 changed")

        let summary = DiffEngine.computeDiff(original: original, modified: modified)

        XCTAssertEqual(summary.additions, 1)
        XCTAssertEqual(summary.deletions, 1)
        XCTAssertEqual(summary.lines.filter { $0.type == .same }.count, 199)

        // The diff must still reconstruct both sides exactly.
        let rebuiltOriginal = summary.lines.filter { $0.type != .added }.map(\.text).joined(separator: "\n")
        let rebuiltModified = summary.lines.filter { $0.type != .removed }.map(\.text).joined(separator: "\n")
        XCTAssertEqual(rebuiltOriginal, original)
        XCTAssertEqual(rebuiltModified, modified)

        XCTAssertEqual(DiffEngine.firstChangedLine(original: original, modified: modified), 100)
    }

    func testDiffEngineHandlesAppendAndEmptySides() {
        let original = "# Title\n\nBody"
        let appended = original + "\n\n## Added\n\nNew text."

        let summary = DiffEngine.computeDiff(original: original, modified: appended)
        XCTAssertEqual(summary.deletions, 0)
        XCTAssertEqual(summary.additions, 4)

        let cleared = DiffEngine.computeDiff(original: original, modified: "")
        XCTAssertGreaterThan(cleared.deletions, 0)
    }

    func testQuoteCandidatesLoosenProgressively() {
        let candidates = DocumentIndex.quoteCandidates(for: "**Install** the CLI\nthen run it")
        XCTAssertEqual(candidates.first, "**Install** the CLI\nthen run it")
        XCTAssertTrue(candidates.contains("Install the CLI"))

        XCTAssertTrue(DocumentIndex.quoteCandidates(for: "  ").isEmpty)
    }

    /// A model can't know the renderer's block IDs, so a quote has to be enough
    /// on its own to find the passage.
    func testResolveLocationByLooseQuote() {
        let markdown = """
        # Setup

        Run **npm install** before anything else.

        # Usage

        Open the app.
        """

        let index = DocumentIndex()
        index.buildIndex(from: markdown)

        let location = DocumentLocation(
            heading: nil,
            quote: "Run npm install before anything else.",
            startLine: nil,
            endLine: nil,
            blockId: nil
        )

        XCTAssertEqual(index.resolveLocation(location)?.headingTitle, "Setup")
    }

    func testProviderErrorSurfacesProviderDetail() {
        let error = AIProviderError.httpStatus(
            provider: .openAI,
            code: 401,
            detail: "Incorrect API key provided."
        )
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.contains("OpenAI"))
        XCTAssertTrue(message.contains("Incorrect API key provided."))

        let detail = AIProviderResponse.errorDetail(
            from: Data("{\"error\": {\"message\": \"API key not valid\"}}".utf8)
        )
        XCTAssertEqual(detail, "API key not valid")

        // Gemini's streaming endpoint wraps the error in an array.
        let arrayDetail = AIProviderResponse.errorDetail(
            from: Data("[{\"error\": {\"message\": \"Quota exceeded\"}}]".utf8)
        )
        XCTAssertEqual(arrayDetail, "Quota exceeded")
    }

    /// The prompt used to hand the model a literal `"blockId": "block-1"`, which
    /// it copied verbatim — and that resolved to the top of the document.
    func testSystemInstructionDoesNotAskForBlockIds() {
        let instruction = AIPromptBuilder.systemInstruction(
            documentText: "# Title",
            selectedText: "Title",
            documentType: "md"
        )

        XCTAssertFalse(instruction.contains("blockId"))
        XCTAssertTrue(instruction.contains("USER SELECTED TEXT"))
        // The edit contract is scoped operations now, not a whole rewritten
        // document — see AIOperationTests.
        XCTAssertTrue(instruction.contains("document_operations"))
        XCTAssertTrue(instruction.contains("3., 2., 1."))
        XCTAssertTrue(instruction.contains("verify that the complete updated document actually contains the requested result"))
    }

    func testEditProposalKeepsOriginalDocumentForRevert() {
        let proposal = AIEditProposal(
            summary: "Reverse the list",
            updatedDocument: "3. Third\n2. Second\n1. First",
            originalDocument: "1. First\n2. Second\n3. Third",
            originalHash: "hash",
            status: .applied
        )

        XCTAssertEqual(proposal.originalDocument, "1. First\n2. Second\n3. Third")
        XCTAssertEqual(proposal.status, .applied)
    }

    // MARK: - Selection as prompt context

    /// Chat replies are rendered with `NSTextView` so their selection can be
    /// read. That only works if each block still sizes itself inside a SwiftUI
    /// stack, so verify real laid-out heights rather than trusting it.
    @MainActor
    func testMarkdownBlocksLayOutWithRealHeights() {
        let markdown = """
        ## A heading

        A paragraph long enough that it has to wrap across several lines when it \
        is laid out in a narrow inspector column like the assistant sidebar uses.

        - First item
        - Second item

        ```
        let value = 1
        ```
        """

        let hosting = NSHostingView(rootView: MarkdownBlocksView(markdown: markdown))
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
        hosting.layoutSubtreeIfNeeded()

        var textViews: [MessageTextView] = []
        func collect(_ view: NSView) {
            if let messageView = view as? MessageTextView { textViews.append(messageView) }
            view.subviews.forEach(collect)
        }
        collect(hosting)

        // heading + paragraph + two list items + code block
        XCTAssertEqual(textViews.count, 5)
        for textView in textViews {
            XCTAssertGreaterThan(
                textView.intrinsicContentSize.height, 0,
                "A block collapsed to zero height: \(textView.string.prefix(30))"
            )
        }

        let heading = textViews[0]
        let wrappingParagraph = textViews[1]
        XCTAssertGreaterThan(
            wrappingParagraph.intrinsicContentSize.height,
            heading.intrinsicContentSize.height,
            "A wrapped paragraph must be taller than a one-line heading"
        )
    }

    /// The whole bug: collapsing a selection — which is what clicking into the
    /// composer does — must not report anything, or the pinned context is lost
    /// exactly when the user goes to type their question.
    @MainActor
    func testCollapsingASelectionReportsNothing() {
        var captured: [String] = []
        let representable = SelectableMarkdownText(
            text: "Hello world",
            font: .systemFont(ofSize: 13),
            color: .labelColor,
            onSelectionChanged: { captured.append($0) }
        )
        let coordinator = representable.makeCoordinator()

        let textView = MessageTextView()
        textView.string = "Hello world"
        let notification = Notification(name: NSTextView.didChangeSelectionNotification, object: textView)

        textView.setSelectedRange(NSRange(location: 0, length: 5))
        coordinator.textViewDidChangeSelection(notification)
        XCTAssertEqual(captured, ["Hello"])

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        coordinator.textViewDidChangeSelection(notification)
        XCTAssertEqual(captured, ["Hello"], "A collapsed selection must not be reported")

        // Whitespace-only selections are not context either.
        textView.setSelectedRange(NSRange(location: 5, length: 1))
        coordinator.textViewDidChangeSelection(notification)
        XCTAssertEqual(captured, ["Hello"])
    }

    func testPromptContextLabelsItsSource() {
        XCTAssertEqual(PromptContext(source: .document, text: "abc").characterCount, 3)
        XCTAssertNotEqual(
            PromptContext.Source.document.label,
            PromptContext.Source.reply.label
        )
    }

    func testTextDirectionUsesFirstStrongCharacter() {
        XCTAssertTrue(TextDirection.isRightToLeft("سلام SwiftUI 6"))
        XCTAssertTrue(TextDirection.isRightToLeft("۱۲۳، متن فارسی API"))
        XCTAssertFalse(TextDirection.isRightToLeft("SwiftUI برای macOS"))
        XCTAssertFalse(TextDirection.isRightToLeft("123 — plain text"))
    }

    @MainActor
    func testVisibleUnicodeEscapesAreRecovered() {
        XCTAssertEqual(
            AIService.decodeUnicodeEscapes(in: "u0633u0644u0627u0645"),
            "سلام"
        )
        XCTAssertEqual(
            AIService.decodeUnicodeEscapes(in: #"\u0633\u0644\u0627\u0645 Swift"#),
            "سلام Swift"
        )
        XCTAssertEqual(AIService.decodeUnicodeEscapes(in: "plain text"), "plain text")
    }


    // MARK: - Prompt attachments

    private func makeTestImage(width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    func testPasteBecomesChipOnlyWhenItWouldBuryThePrompt() {
        XCTAssertFalse(PromptAttachmentLimits.shouldBecomeChip("a short paste"))
        XCTAssertFalse(PromptAttachmentLimits.shouldBecomeChip(String(repeating: "x", count: 100)))

        XCTAssertTrue(PromptAttachmentLimits.shouldBecomeChip(String(repeating: "x", count: 400)))
        // Many short lines bury the prompt just as effectively as one long one.
        XCTAssertTrue(PromptAttachmentLimits.shouldBecomeChip(
            (1...12).map { "line \($0)" }.joined(separator: "\n")
        ))
    }

    func testPastedItemDescribesItself() {
        let item = PastedTextItem(number: 3, text: "first line\nsecond line")
        XCTAssertEqual(item.title, "Pasted text 3")
        XCTAssertEqual(item.lineCount, 2)
        XCTAssertEqual(item.previewLine, "first line")
        XCTAssertTrue(item.summary.contains("2 lines"))
    }

    func testImageLoaderDownscalesOversizedImages() async throws {
        let oversized = makeTestImage(width: 3200, height: 1600)
        let attachment = try await ImageAttachmentLoader.load(from: oversized, fileName: "shot.png")

        // The original dimensions are reported to the user…
        XCTAssertEqual(attachment.pixelSize.width, 3200)
        XCTAssertEqual(attachment.dimensionsDescription, "3200 × 1600")

        // …but the bytes actually sent are capped on the long edge.
        let sent = try XCTUnwrap(NSImage(data: attachment.data))
        let sentRep = try XCTUnwrap(sent.representations.first)
        XCTAssertLessThanOrEqual(
            CGFloat(max(sentRep.pixelsWide, sentRep.pixelsHigh)),
            PromptAttachmentLimits.maximumImageDimension
        )
        XCTAssertEqual(sentRep.pixelsWide, 1568)
        XCTAssertEqual(sentRep.pixelsHigh, 784)
        XCTAssertLessThanOrEqual(attachment.data.count, PromptAttachmentLimits.maximumImageBytes)
        XCTAssertNotNil(attachment.thumbnail)
    }

    func testImageLoaderLeavesSmallImagesAlone() async throws {
        let small = makeTestImage(width: 320, height: 200)
        let attachment = try await ImageAttachmentLoader.load(from: small, fileName: "small.png")

        let sent = try XCTUnwrap(NSImage(data: attachment.data))
        let rep = try XCTUnwrap(sent.representations.first)
        XCTAssertEqual(rep.pixelsWide, 320)
        XCTAssertEqual(rep.pixelsHigh, 200)
        XCTAssertEqual(attachment.mimeType, "image/png")
    }

    func testImageAttachmentSurvivesCodableRoundTrip() async throws {
        let attachment = try await ImageAttachmentLoader.load(
            from: makeTestImage(width: 40, height: 40),
            fileName: "tiny.png"
        )

        let encoded = try JSONEncoder().encode(attachment)
        let decoded = try JSONDecoder().decode(AIImageAttachment.self, from: encoded)

        XCTAssertEqual(decoded.id, attachment.id)
        XCTAssertEqual(decoded.fileName, "tiny.png")
        XCTAssertEqual(decoded.data, attachment.data)
        // The thumbnail is derived, never stored — but it must come back.
        XCTAssertNotNil(decoded.thumbnail)
    }

    func testOnlyVisionModelsAcceptImages() {
        XCTAssertTrue(AIModelCatalog.supportsImages(AIModel(id: "gemini-flash-latest", displayName: "", provider: .gemini)))
        XCTAssertTrue(AIModelCatalog.supportsImages(AIModel(id: "gpt-4o", displayName: "", provider: .openAI)))
        XCTAssertTrue(AIModelCatalog.supportsImages(AIModel(id: "gpt-5-mini", displayName: "", provider: .openAI)))
        XCTAssertFalse(AIModelCatalog.supportsImages(AIModel(id: "gpt-3.5-turbo", displayName: "", provider: .openAI)))
    }

    func testProvidersEncodeImagesInTheirOwnWireFormat() async throws {
        let image = try await ImageAttachmentLoader.load(
            from: makeTestImage(width: 20, height: 20),
            fileName: "dot.png"
        )

        // Gemini: inline_data parts, before the text they refer to.
        let geminiParts = GeminiProvider.parts(text: "what is this?", images: [image])
        XCTAssertEqual(geminiParts.count, 2)
        let inline = try XCTUnwrap(geminiParts[0]["inline_data"] as? [String: Any])
        XCTAssertEqual(inline["mime_type"] as? String, "image/png")
        XCTAssertEqual(inline["data"] as? String, image.base64)
        XCTAssertEqual(geminiParts[1]["text"] as? String, "what is this?")

        // Gemini rejects an empty parts array outright.
        XCTAssertFalse(GeminiProvider.parts(text: "", images: []).isEmpty)

        // OpenAI: a text-only turn stays a plain string.
        XCTAssertEqual(OpenAIProvider.content(text: "hello", images: []) as? String, "hello")

        let openAIParts = try XCTUnwrap(
            OpenAIProvider.content(text: "what is this?", images: [image]) as? [[String: Any]]
        )
        XCTAssertEqual(openAIParts.count, 2)
        XCTAssertEqual(openAIParts[0]["type"] as? String, "text")
        XCTAssertEqual(openAIParts[1]["type"] as? String, "image_url")
        let urlBox = try XCTUnwrap(openAIParts[1]["image_url"] as? [String: Any])
        let dataURL = try XCTUnwrap(urlBox["url"] as? String)
        XCTAssertTrue(dataURL.hasPrefix("data:image/png;base64,"))

        // Both payloads have to survive JSONSerialization — an NSImage or a
        // stray non-JSON type here is a runtime crash at request time.
        XCTAssertTrue(JSONSerialization.isValidJSONObject(["contents": [["parts": geminiParts]]]))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(["messages": [["content": openAIParts]]]))
    }


    // MARK: - Markdown formatting

    func testToggleInlineWrapsAndUnwraps() {
        let text = "make this bold please"
        let range = (text as NSString).range(of: "bold")

        let bolded = MarkdownFormatter.toggleInline(text, range: range, marker: "**")
        XCTAssertEqual(bolded.text, "make this **bold** please")
        XCTAssertEqual((bolded.text as NSString).substring(with: bolded.selectedRange), "bold")

        // Toggling again with the selection still on the word unwraps it, even
        // though the markers are now outside the selection.
        let unbolded = MarkdownFormatter.toggleInline(
            bolded.text, range: bolded.selectedRange, marker: "**"
        )
        XCTAssertEqual(unbolded.text, text)

        // And unwraps when the markers are inside the selection too.
        let wholeSpan = (bolded.text as NSString).range(of: "**bold**")
        XCTAssertEqual(
            MarkdownFormatter.toggleInline(bolded.text, range: wholeSpan, marker: "**").text,
            text
        )
    }

    func testToggleInlineOnEmptySelectionLeavesCaretInside() {
        let edit = MarkdownFormatter.toggleInline("ab", range: NSRange(location: 1, length: 0), marker: "==")
        XCTAssertEqual(edit.text, "a====b")
        XCTAssertEqual(edit.selectedRange, NSRange(location: 3, length: 0))
    }

    func testHeadingLevelsReplaceRatherThanStack() {
        let text = "Title\nbody"
        let range = NSRange(location: 0, length: 0)

        let h1 = MarkdownFormatter.setHeading(text, range: range, level: 1)
        XCTAssertEqual(h1.text, "# Title\nbody")

        let h3 = MarkdownFormatter.setHeading(h1.text, range: range, level: 3)
        XCTAssertEqual(h3.text, "### Title\nbody", "Levels must replace, not accumulate")

        let cleared = MarkdownFormatter.setHeading(h3.text, range: range, level: 0)
        XCTAssertEqual(cleared.text, "Title\nbody")
    }

    func testLinePrefixTogglesAcrossASelection() {
        let text = "one\ntwo\nthree"
        let range = NSRange(location: 0, length: (text as NSString).length)

        let quoted = MarkdownFormatter.toggleLinePrefix(text, range: range, prefix: "> ")
        XCTAssertEqual(quoted.text, "> one\n> two\n> three")

        let unquoted = MarkdownFormatter.toggleLinePrefix(quoted.text, range: quoted.selectedRange, prefix: "> ")
        XCTAssertEqual(unquoted.text, text)
    }

    func testOrderedListNumbersSequentially() {
        let text = "alpha\nbeta\ngamma"
        let range = NSRange(location: 0, length: (text as NSString).length)

        let numbered = MarkdownFormatter.toggleOrderedList(text, range: range)
        XCTAssertEqual(numbered.text, "1. alpha\n2. beta\n3. gamma")

        let plain = MarkdownFormatter.toggleOrderedList(numbered.text, range: numbered.selectedRange)
        XCTAssertEqual(plain.text, text)
    }

    func testSwitchingListTypeDoesNotKeepTheOldMarker() {
        let bulleted = MarkdownFormatter.toggleLinePrefix("a\nb", range: NSRange(location: 0, length: 3), prefix: "- ")
        XCTAssertEqual(bulleted.text, "- a\n- b")

        let numbered = MarkdownFormatter.toggleOrderedList(bulleted.text, range: bulleted.selectedRange)
        XCTAssertEqual(numbered.text, "1. a\n2. b")
    }

    func testInsertLinkSelectsTheURL() {
        let text = "see docs"
        let edit = MarkdownFormatter.insertLink(text, range: (text as NSString).range(of: "docs"))
        XCTAssertEqual(edit.text, "see [docs](https://)")
        XCTAssertEqual((edit.text as NSString).substring(with: edit.selectedRange), "https://")
    }

    func testBlockDirectionWrapsAndToggles() {
        let text = "سلام دنیا"
        let range = NSRange(location: 0, length: 0)

        let rtl = MarkdownFormatter.setBlockDirection(text, range: range, direction: .rightToLeft)
        XCTAssertTrue(rtl.text.hasPrefix("<div dir=\"rtl\" markdown=\"1\">"))
        XCTAssertTrue(rtl.text.contains(text))
        XCTAssertTrue(rtl.text.hasSuffix("</div>"))

        // Same direction again removes the wrapper.
        let unwrapped = MarkdownFormatter.setBlockDirection(
            rtl.text, range: NSRange(location: 0, length: (rtl.text as NSString).length), direction: .rightToLeft
        )
        XCTAssertEqual(unwrapped.text, text)

        // The other direction re-wraps rather than nesting.
        let flipped = MarkdownFormatter.setBlockDirection(
            rtl.text, range: NSRange(location: 0, length: (rtl.text as NSString).length), direction: .leftToRight
        )
        XCTAssertTrue(flipped.text.contains("dir=\"ltr\""))
        XCTAssertFalse(flipped.text.contains("dir=\"rtl\""))
    }

    // MARK: - Tables

    private var sampleTable: String {
        """
        | Name | Age |
        | --- | --- |
        | Ada | 36 |
        | Alan | 41 |
        """
    }

    func testTableContextFindsRowsAndColumns() throws {
        let caret = (sampleTable as NSString).range(of: "Alan").location
        let table = try XCTUnwrap(MarkdownFormatter.tableContext(in: sampleTable, at: caret))

        XCTAssertEqual(table.columnCount, 2)
        XCTAssertEqual(table.rows.count, 3, "header plus two body rows")
        XCTAssertEqual(table.rows[0], ["Name", "Age"])
        XCTAssertEqual(table.caretRow, 2)
        XCTAssertEqual(table.caretColumn, 0)

        // Text outside any table has no context, so the panel can disable.
        XCTAssertNil(MarkdownFormatter.tableContext(in: "just a paragraph", at: 3))
    }

    func testAddAndDeleteTableRow() throws {
        let caret = (sampleTable as NSString).range(of: "Ada").location
        let added = try XCTUnwrap(MarkdownFormatter.addTableRow(sampleTable, at: caret))
        XCTAssertEqual(added.text.components(separatedBy: "\n").count, 5)

        let deleted = try XCTUnwrap(MarkdownFormatter.deleteTableRow(added.text, at: caret))
        XCTAssertEqual(deleted.text.components(separatedBy: "\n").count, 4)

        // The header row must never be deletable — that would destroy the table.
        let headerCaret = (sampleTable as NSString).range(of: "Name").location
        XCTAssertNil(MarkdownFormatter.deleteTableRow(sampleTable, at: headerCaret))
    }

    func testAddAndDeleteTableColumn() throws {
        let caret = (sampleTable as NSString).range(of: "Ada").location
        let added = try XCTUnwrap(MarkdownFormatter.addTableColumn(sampleTable, at: caret))
        let addedTable = try XCTUnwrap(MarkdownFormatter.tableContext(in: added.text, at: caret))
        XCTAssertEqual(addedTable.columnCount, 3)
        XCTAssertEqual(addedTable.rows[0].count, 3)

        let deleted = try XCTUnwrap(MarkdownFormatter.deleteTableColumn(added.text, at: caret))
        let deletedTable = try XCTUnwrap(MarkdownFormatter.tableContext(in: deleted.text, at: caret))
        XCTAssertEqual(deletedTable.columnCount, 2)
    }

    func testTableColumnAlignment() throws {
        let caret = (sampleTable as NSString).range(of: "Ada").location
        let aligned = try XCTUnwrap(
            MarkdownFormatter.setTableColumnAlignment(sampleTable, at: caret, alignment: .center)
        )
        XCTAssertTrue(aligned.text.contains(":---:"))

        let context = try XCTUnwrap(MarkdownFormatter.tableContext(in: aligned.text, at: caret))
        XCTAssertEqual(context.alignments[0], .center)
        XCTAssertEqual(context.alignments[1], .none)
    }

    func testInsertedTableIsParseableByItsOwnParser() throws {
        let edit = MarkdownFormatter.insertTable("intro", range: NSRange(location: 0, length: 0), rows: 2, columns: 3)
        let caret = (edit.text as NSString).range(of: "Column 1").location
        let table = try XCTUnwrap(MarkdownFormatter.tableContext(in: edit.text, at: caret))
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.rows.count, 3, "header plus the two requested body rows")
    }

    // MARK: - Persian text tools

    func testNormalizeLettersReplacesArabicForms() {
        XCTAssertEqual(PersianTextTools.normalizeLetters("كتاب"), "کتاب")
        XCTAssertEqual(PersianTextTools.normalizeLetters("يك"), "یک")
        XCTAssertEqual(PersianTextTools.normalizeLetters("١٢٣"), "۱۲۳")
        XCTAssertEqual(PersianTextTools.normalizeLetters("hello"), "hello")
    }

    /// A half-space binds to the letter before it, making one grapheme
    /// cluster — and replacing by substring could not see inside one. So the
    /// fix worked on `كتاب` but silently did nothing to `مي‌شود`, i.e. it
    /// failed on the words that already had a نیم‌فاصله, which is most Persian
    /// prose.
    func testNormalizeLettersReachesLettersBoundToAHalfSpace() {
        let zwnj = PersianTextTools.zwnj
        XCTAssertEqual(
            PersianTextTools.normalizeLetters("مي\(zwnj)شود"),
            "می\(zwnj)شود"
        )
        XCTAssertEqual(
            PersianTextTools.normalizeLetters("نمي\(zwnj)كنم"),
            "نمی\(zwnj)کنم"
        )
        // The half-space itself must survive.
        XCTAssertTrue(PersianTextTools.normalizeLetters("مي\(zwnj)شود").unicodeScalars.contains { $0.value == 0x200C })
    }

    func testDigitConversionReachesDigitsBoundToAHalfSpace() {
        let zwnj = PersianTextTools.zwnj
        XCTAssertEqual(
            PersianTextTools.toPersianDigits("صفحه\(zwnj)12"),
            "صفحه\(zwnj)۱۲"
        )
    }

    func testDigitConversionRoundTrips() {
        XCTAssertEqual(PersianTextTools.toPersianDigits("Room 101"), "Room ۱۰۱")
        XCTAssertEqual(PersianTextTools.toLatinDigits("Room ۱۰۱"), "Room 101")
        XCTAssertEqual(PersianTextTools.toLatinDigits("١٢٣"), "123")
    }

    func testZeroWidthNonJoinerAttachesPrefixesAndSuffixes() {
        let zwnj = PersianTextTools.zwnj
        XCTAssertEqual(PersianTextTools.applyZeroWidthNonJoiner("می رود"), "می\(zwnj)رود")
        XCTAssertEqual(PersianTextTools.applyZeroWidthNonJoiner("نمی خواهم"), "نمی\(zwnj)خواهم")
        XCTAssertEqual(PersianTextTools.applyZeroWidthNonJoiner("کتاب ها"), "کتاب\(zwnj)ها")
        XCTAssertEqual(PersianTextTools.applyZeroWidthNonJoiner("بزرگ تر"), "بزرگ\(zwnj)تر")

        // A word that merely starts with those letters must not be glued.
        XCTAssertEqual(PersianTextTools.applyZeroWidthNonJoiner("میز بزرگ"), "میز بزرگ")
    }

    func testPunctuationNormalization() {
        XCTAssertEqual(PersianTextTools.normalizePunctuation("سلام, دنیا"), "سلام، دنیا")
        XCTAssertEqual(PersianTextTools.normalizePunctuation("چطوری ?"), "چطوری؟")
    }

    func testTidyWhitespaceKeepsMarkdownHardBreaks() {
        XCTAssertEqual(PersianTextTools.tidyWhitespace("a    b"), "a b")
        // One trailing space is noise and goes.
        XCTAssertEqual(PersianTextTools.tidyWhitespace("trailing \nnext"), "trailing\nnext")
        // Two or more trailing spaces are a Markdown hard break: kept, and
        // normalised to the canonical two.
        XCTAssertEqual(PersianTextTools.tidyWhitespace("break  \nnext"), "break  \nnext")
        XCTAssertEqual(PersianTextTools.tidyWhitespace("break   \nnext"), "break  \nnext")
    }

    // MARK: - Persian cleanup must leave everything else alone

    /// Converting every `,` and `?` in the document rewrote the English half of
    /// a bilingual document: "Hello, world" became "Hello، world".
    func testPunctuationLeavesEnglishAlone() {
        XCTAssertEqual(
            PersianTextTools.normalizePunctuation("Hello, world; ok?"),
            "Hello, world; ok?"
        )
        // Persian punctuation still converts, including on the Persian side of
        // a mixed line.
        XCTAssertEqual(
            PersianTextTools.normalizePunctuation("Hello, world. سلام, دنیا"),
            "Hello, world. سلام، دنیا"
        )
    }

    /// These transforms are about prose. Run over a document they also rewrote
    /// code — `arr[1,2]` became `arr[1،2]`.
    func testCleanupLeavesCodeAlone() {
        let source = """
        سلام, دنیا

        ```swift
        let pairs = [1, 2]   // كتاب
        ```

        متن `arr[1,2]` ادامه
        """

        let cleaned = PersianTextTools.fixAll(source)
        XCTAssertTrue(cleaned.contains("let pairs = [1, 2]"), "Fenced code must survive: \(cleaned)")
        XCTAssertTrue(cleaned.contains("// كتاب"), "Even Arabic letters inside code are code")
        XCTAssertTrue(cleaned.contains("`arr[1,2]`"), "Inline code must survive: \(cleaned)")
        // The prose around it is still fixed.
        XCTAssertTrue(cleaned.contains("سلام، دنیا"), "Got: \(cleaned)")
    }

    func testDigitConversionSkipsCode() {
        let source = "شماره 12 است\n\n```js\nconst x = 42;\n```"
        let converted = PersianTextTools.outsideCode(source, PersianTextTools.toPersianDigits)

        XCTAssertTrue(converted.contains("شماره ۱۲ است"), "Got: \(converted)")
        XCTAssertTrue(converted.contains("const x = 42;"), "Code digits are code: \(converted)")
    }

    // MARK: - The Persian panel's diagnosis

    func testAnalyzerFindsRealIssuesWithCounts() {
        let text = "مي‌شود كتاب و می رود, بعد"
        let issues = PersianTextAnalyzer.analyze(text)

        let kinds = Set(issues.map(\.kind))
        XCTAssertTrue(kinds.contains(.arabicLetters), "ي and ك are present")
        XCTAssertTrue(kinds.contains(.missingZWNJ), "می رود needs a half-space")
        XCTAssertTrue(kinds.contains(.latinPunctuation), "the comma is beside Persian text")

        let letters = try? XCTUnwrap(issues.first { $0.kind == .arabicLetters })
        XCTAssertEqual(letters?.count, 2, "One ي and one ك")
    }

    func testAnalyzerReportsCleanTextAsClean() {
        // Already correct: Persian letters, half-spaces, Persian punctuation.
        let clean = "می\(PersianTextTools.zwnj)رود، بعد کتاب\(PersianTextTools.zwnj)ها"
        XCTAssertTrue(
            PersianTextAnalyzer.analyze(clean).isEmpty,
            "Got: \(PersianTextAnalyzer.analyze(clean).map(\.kind))"
        )
        XCTAssertTrue(PersianTextAnalyzer.isClean(clean))
    }

    func testAnalyzerIgnoresTextWithNoPersianAtAll() {
        XCTAssertTrue(PersianTextAnalyzer.analyze("Hello, world; ok? arr[1,2]").isEmpty)
    }

    func testAnalyzerIgnoresProblemsThatOnlyExistInsideCode() {
        let text = "متن درست است\n\n```\nlet a = [1, 2]; كتاب\n```"
        let kinds = Set(PersianTextAnalyzer.analyze(text).map(\.kind))
        XCTAssertFalse(kinds.contains(.arabicLetters), "The ك is inside code")
        XCTAssertFalse(kinds.contains(.latinPunctuation), "The comma is inside code")
    }

    /// Every issue carries a worked example, because the change it describes is
    /// invisible on screen — and an example that shows nothing changing would
    /// be worse than none.
    func testEveryReportedIssueCarriesADistinctExample() throws {
        let text = "مي‌شود و می رود, كتاب ها  بعد"
        let issues = PersianTextAnalyzer.analyze(text)
        XCTAssertFalse(issues.isEmpty)

        for issue in issues {
            let example = try XCTUnwrap(issue.example, "\(issue.kind) reported no example")
            XCTAssertNotEqual(
                example.before, example.after,
                "\(issue.kind)'s example shows no change"
            )
            XCTAssertFalse(example.before.isEmpty)
        }
    }

    /// The wiring property: the command each issue offers as its "Fix" must
    /// actually make that issue go away. A row whose button does nothing is
    /// exactly the failure this panel was rebuilt to escape.
    func testEachIssuesFixCommandActuallyResolvesThatIssue() throws {
        let text = "مي‌شود كتاب و می رود, بعد  و کتاب ها"
        let issues = PersianTextAnalyzer.analyze(text)
        XCTAssertFalse(issues.isEmpty, "The sample should be dirty enough to test with")

        for issue in issues {
            let transform = try XCTUnwrap(
                transformFor(issue.kind.command),
                "\(issue.kind) offers a command with no transform behind it"
            )
            let fixed = PersianTextTools.outsideCode(text, transform)
            let remaining = PersianTextAnalyzer.analyze(fixed).first { $0.kind == issue.kind }

            XCTAssertLessThan(
                remaining?.count ?? 0, issue.count,
                "Fixing \(issue.kind) left just as many behind"
            )
        }
    }

    func testFixAllClearsEverythingItReported() {
        let text = "مي‌شود كتاب و می رود, بعد  و کتاب ها"
        XCTAssertFalse(PersianTextAnalyzer.analyze(text).isEmpty)

        let fixed = PersianTextTools.fixAll(text)
        XCTAssertTrue(
            PersianTextAnalyzer.analyze(fixed).isEmpty,
            "Still reported after Fix all: \(PersianTextAnalyzer.analyze(fixed).map { "\($0.kind)×\($0.count)" })"
        )
    }

    func testDigitCountsIgnoreCode() {
        let counts = PersianTextTools.digitCounts(in: "۱۲ و 3\n\n```\n9999\n```")
        XCTAssertEqual(counts.persian, 2)
        XCTAssertEqual(counts.latin, 1, "The 9999 is inside code")
    }

    /// Mirrors how `DocumentView` maps a command to a transform, so the test
    /// exercises the same routing the panel uses.
    private func transformFor(_ command: FormatCommand) -> ((String) -> String)? {
        switch command {
        case .persianFixAll: return PersianTextTools.fixAll
        case .persianNormalizeLetters: return PersianTextTools.normalizeLetters
        case .persianZWNJ: return PersianTextTools.applyZeroWidthNonJoiner
        case .persianPunctuation: return PersianTextTools.normalizePunctuation
        case .persianTidyWhitespace: return PersianTextTools.tidyWhitespace
        default: return nil
        }
    }

    func testPersianDetectionAndDirectionMarks() {
        XCTAssertTrue(PersianTextTools.containsPersian("سلام"))
        XCTAssertFalse(PersianTextTools.containsPersian("hello 123"))

        let pinned = PersianTextTools.pinDirection("123", rightToLeft: true)
        XCTAssertTrue(pinned.hasPrefix(PersianTextTools.rlm))
        XCTAssertEqual(PersianTextTools.removeDirectionMarks(pinned), "123")
    }


    // MARK: - Document templates

    /// A template exists to give a new file real blocks to click on, so each
    /// one has to actually parse into more than nothing.
    func testEveryStarterTemplateProducesRealBlocks() {
        XCTAssertFalse(DocumentTemplate.all.isEmpty)

        for template in DocumentTemplate.all {
            XCTAssertFalse(
                template.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(template.id) is empty"
            )

            let index = DocumentIndex()
            index.buildIndex(from: template.body)
            XCTAssertFalse(index.blocks.isEmpty, "\(template.id) produced no blocks")

            XCTAssertFalse(template.title.isEmpty)
            XCTAssertFalse(template.detail.isEmpty)
        }

        XCTAssertEqual(
            Set(DocumentTemplate.all.map(\.id)).count,
            DocumentTemplate.all.count,
            "Template ids must be unique — they are the ForEach identity"
        )
    }

    func testPersianTemplateIsWrappedRightToLeft() throws {
        let persian = try XCTUnwrap(DocumentTemplate.all.first { $0.id == "persian" })
        XCTAssertTrue(persian.body.contains("dir=\"rtl\""))
        XCTAssertTrue(PersianTextTools.containsPersian(persian.body))
    }

    func testChecklistTemplateUsesTaskSyntax() throws {
        let checklist = try XCTUnwrap(DocumentTemplate.all.first { $0.id == "checklist" })
        XCTAssertTrue(checklist.body.contains("- [ ] "))
    }

    func testTableTemplateIsParseableAsATable() throws {
        let table = try XCTUnwrap(DocumentTemplate.all.first { $0.id == "table" })
        let caret = (table.body as NSString).range(of: "Column 1").location
        let context = try XCTUnwrap(MarkdownFormatter.tableContext(in: table.body, at: caret))
        XCTAssertEqual(context.columnCount, 3)
    }


    /// ⌘N produced a document with no text and no file, which used to be routed
    /// to a drop-target screen instead of the editor — so the toolbar, panels,
    /// and templates never appeared, and its New button only made another copy
    /// of the same screen.
    func testEmptyUnsavedDocumentStillGetsTheEditor() {
        XCTAssertTrue(DocumentStarter.shouldOffer(text: "", fileExtension: "md"))
        XCTAssertTrue(DocumentStarter.shouldOffer(text: "   \n\n  ", fileExtension: "md"))
        XCTAssertTrue(DocumentStarter.shouldOffer(text: "", fileExtension: "markdown"))

        // A document with content renders normally.
        XCTAssertFalse(DocumentStarter.shouldOffer(text: "# Title", fileExtension: "md"))

        // Mermaid keeps its own empty behaviour.
        XCTAssertFalse(DocumentStarter.shouldOffer(text: "", fileExtension: "mmd"))
        XCTAssertFalse(DocumentStarter.shouldOffer(text: "", fileExtension: "MMD"))
    }

    @MainActor
    func testStarterLaysOutItsTemplates() {
        let hosting = NSHostingView(
            rootView: DocumentStarterView(onChoose: { _ in }, onOpenSource: {})
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 640)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hosting.fittingSize.height, 0)
        XCTAssertFalse(hosting.subviews.isEmpty, "The starter rendered nothing")
    }


    // MARK: - Resolving a preview selection

    /// Selecting text in Preview and pressing a formatting button did nothing
    /// useful: the preview reports *rendered* text, which was matched against
    /// *Markdown source* with a plain substring search. Anything carrying
    /// formatting never matched, and the range fell back to offset 0.
    func testPreviewSelectionResolvesThroughMarkdownSyntax() throws {
        let source = """
        # Meeting notes

        **Date:** 2026 Aug 12
        **Attendees:**

        ## Discussion

        - first *item* here
        """

        // Plain text still matches exactly.
        let heading = try XCTUnwrap(SourceSelectionResolver.range(of: "Meeting notes", in: source))
        XCTAssertEqual((source as NSString).substring(with: heading), "Meeting notes")

        // The case that was broken: rendered text spanning bold markers.
        let date = try XCTUnwrap(SourceSelectionResolver.range(of: "Date: 2026 Aug 12", in: source))
        let dateText = (source as NSString).substring(with: date)
        XCTAssertTrue(dateText.contains("Date:"))
        XCTAssertTrue(dateText.contains("2026 Aug 12"))
        XCTAssertFalse(dateText.contains("#"), "The range must not spill into other blocks")

        // A list item, whose bullet is rendered rather than literal.
        let item = try XCTUnwrap(SourceSelectionResolver.range(of: "first item here", in: source))
        let itemText = (source as NSString).substring(with: item)
        XCTAssertTrue(itemText.hasPrefix("first"))
        XCTAssertTrue(itemText.hasSuffix("here"))

        // Genuinely absent text resolves to nothing rather than to offset 0.
        XCTAssertNil(SourceSelectionResolver.range(of: "not in this document", in: source))
        XCTAssertNil(SourceSelectionResolver.range(of: "   ", in: source))
    }

    func testResolvedRangeSurvivesAFormattingRoundTrip() throws {
        let source = "Some **bold text** in a line."
        let range = try XCTUnwrap(SourceSelectionResolver.range(of: "bold text", in: source))

        // The range excludes the surrounding markers, so toggling bold on it
        // unwraps rather than double-wrapping.
        XCTAssertEqual((source as NSString).substring(with: range), "bold text")
        let toggled = MarkdownFormatter.toggleInline(source, range: range, marker: "**")
        XCTAssertEqual(toggled.text, "Some bold text in a line.")
    }

    func testResolverHandlesWrappedAndPersianSelections() throws {
        // Rendered text collapses a source line break into a space.
        let wrapped = "A sentence that\ncontinues on the next line."
        let range = try XCTUnwrap(
            SourceSelectionResolver.range(of: "sentence that continues on", in: wrapped)
        )
        XCTAssertTrue((wrapped as NSString).substring(with: range).contains("continues"))

        let persian = "# عنوان\n\nمتن **پررنگ** اینجاست."
        let persianRange = try XCTUnwrap(
            SourceSelectionResolver.range(of: "متن پررنگ اینجاست.", in: persian)
        )
        let matched = (persian as NSString).substring(with: persianRange)
        XCTAssertTrue(matched.hasPrefix("متن"))
        XCTAssertTrue(matched.hasSuffix("اینجاست."))
    }

    @MainActor
    func testDocumentNavigatorSearch() {
        let text = """
        MarkView is a native viewer.
        MarkView supports Markdown and Mermaid.
        Another line without match.
        """

        let navigator = DocumentNavigator()
        navigator.performSearch(query: "MarkView", in: text)

        XCTAssertEqual(navigator.searchMatches.count, 2)
        XCTAssertEqual(navigator.selectedMatchIndex, 0)

        navigator.nextMatch()
        XCTAssertEqual(navigator.selectedMatchIndex, 1)

        navigator.nextMatch()
        XCTAssertEqual(navigator.selectedMatchIndex, 0)
    }

    // MARK: - View modes

    /// Preview, Editor, Source — the rendered page, the thing you edit, and the
    /// Markdown behind it, in that order.
    func testThereAreThreeModesInReadingOrder() {
        XCTAssertEqual(ViewMode.allCases.map(\.rawValue), ["Preview", "Editor", "Source"])
    }

    func testMermaidFallsBackFromTheEditorToThePreview() {
        // The canvas has no block model for a diagram, so it would show
        // nothing at all.
        XCTAssertEqual(ViewMode.effective(stored: .editor, fileExtension: "mmd"), .preview)
        XCTAssertEqual(ViewMode.effective(stored: .editor, fileExtension: "MMD"), .preview)

        // Every other combination is left alone.
        XCTAssertEqual(ViewMode.effective(stored: .editor, fileExtension: "md"), .editor)
        XCTAssertEqual(ViewMode.effective(stored: .source, fileExtension: "mmd"), .source)
        XCTAssertEqual(ViewMode.effective(stored: .preview, fileExtension: "mmd"), .preview)
    }

    @MainActor
    func testNavigatingInTheEditorFindsTextRatherThanALineNumber() {
        let markdown = "# Setup\n\nRun **npm install** before anything else.\n\n# Usage"
        let navigator = DocumentNavigator()
        navigator.updateDocumentText(markdown)

        // The canvas holds *rendered* text: no "#", no "**".
        let canvas = NSTextView()
        canvas.string = "Setup\nRun npm install before anything else.\nUsage"
        navigator.attachCanvas(canvas)

        navigator.navigateToLocation(
            DocumentLocation(
                heading: "Setup",
                quote: "Run **npm install** before anything else.",
                startLine: 3,
                endLine: 3,
                blockId: nil
            ),
            text: markdown,
            viewMode: .editor,
            reduceMotion: true
        )

        let selected = (canvas.string as NSString).substring(with: canvas.selectedRange())
        XCTAssertEqual(
            selected,
            "Run npm install before anything else.",
            "A source line number means nothing in the canvas; it has to find the words"
        )
    }

    @MainActor
    func testEditorNavigationDoesNothingWhenTheTextIsAbsent() {
        let navigator = DocumentNavigator()
        let canvas = NSTextView()
        canvas.string = "Nothing relevant here."
        navigator.attachCanvas(canvas)

        navigator.navigateToLocation(
            DocumentLocation(heading: nil, quote: "not present", startLine: nil, endLine: nil, blockId: nil),
            text: "",
            viewMode: .editor,
            reduceMotion: true
        )
        XCTAssertEqual(canvas.selectedRange().length, 0, "A miss must not select something arbitrary")
    }
}
