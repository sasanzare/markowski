import AppKit
import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    /// The original rendered preview: read-only, WebView, Mermaid and all.
    case preview = "Preview"
    /// The WYSIWYG canvas — the document as something to edit.
    case editor = "Editor"
    /// Raw Markdown.
    case source = "Source"

    var id: String { rawValue }

    /// The mode that can actually be shown. Mermaid documents have no block
    /// model, so the canvas would render them as nothing — they fall back to
    /// the rendered preview rather than to an empty editor.
    static func effective(stored: ViewMode, fileExtension: String) -> ViewMode {
        if stored == .editor, fileExtension.lowercased() == "mmd" { return .preview }
        return stored
    }
}

struct DocumentView: View {
    @Binding var document: MarkViewDocument
    let fileURL: URL?

    @AppStorage("showAISidebar") private var showAISidebar = false
    @AppStorage("showFormatSidebar") private var showFormatSidebar = false
    @AppStorage("formatSidebarWidth") private var storedFormatSidebarWidth = 232.0
    @AppStorage("aiInspectorWidth") private var storedInspectorWidth = 380.0
    @StateObject private var aiService = AIService()
    @StateObject private var navigator = DocumentNavigator()
    @StateObject private var fileWatcher = FileWatcher()
    /// Follows the caret into a table in the canvas, so the formatting panel
    /// can act on it. A table lives in a text attachment, so nothing reading
    /// Markdown source can see the caret inside one.
    @StateObject private var tableBridge = TableSelectionBridge()
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("documentViewMode") private var storedViewMode = ViewMode.editor.rawValue
    @State private var zoomLevel = 1.0
    @State private var fontSize: CGFloat = 13
    @State private var selectedText: String?
    @State private var selectionRequest: PreviewSelectionRequest?
    @State private var refreshTrigger = UUID()
    @State private var dragStartWidth: Double?
    @State private var formatDragStartWidth: Double?
    @State private var formatNotice: String?
    @State private var formatNoticeToken = UUID()
    /// The text we last knew was on disk, for telling our own autosave apart
    /// from someone else editing the file.
    @State private var lastSyncedText: String?
    /// Set when the file changed underneath edits we hadn't saved yet.
    @State private var externalChangeAvailable = false
    /// The Persian problems in whatever the panel is currently scoped to.
    ///
    /// Held in state rather than computed in `body`: analysing the whole
    /// document is real work, and SwiftUI evaluates a body far more often than
    /// the text actually changes.
    @State private var persianIssues: [PersianIssue] = []
    @State private var persianDigitCounts: (latin: Int, persian: Int) = (0, 0)
    @State private var persianScanToken = UUID()

    private let inspectorMinimumWidth = 320.0
    private let inspectorMaximumWidth = 480.0
    private let formatSidebarMinimumWidth = 196.0
    private let formatSidebarMaximumWidth = 340.0

    var body: some View {
        ZStack {
            MarkViewMaterialBackdrop()
                .ignoresSafeArea()

            HStack(spacing: 0) {
                if showFormatSidebar {
                    FormattingSidebar(
                        tableContext: currentTableContext,
                        hasSelection: currentEditRange.length > 0,
                        notice: formatNotice,
                        selectionContainsPersian: PersianTextTools.containsPersian(currentScopeText),
                        persianIssues: persianIssues,
                        persianDigitCounts: persianDigitCounts,
                        onCommand: applyFormatCommand,
                        onClose: {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08)) {
                                showFormatSidebar = false
                            }
                        }
                    )
                    .frame(width: formatSidebarWidth)
                    .background(MarkViewDesign.sidebarSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(MarkViewDesign.strongBorder, lineWidth: 0.8)
                            .allowsHitTesting(false)
                    )
                    .shadow(color: MarkViewDesign.shadow.opacity(0.58), radius: 14, y: 5)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    // Dragging right widens a leading panel, so the translation
                    // is added here where the trailing inspector subtracts it.
                    InspectorResizeHandle { translation in
                        if formatDragStartWidth == nil {
                            formatDragStartWidth = formatSidebarWidth
                        }
                        let startingWidth = formatDragStartWidth ?? formatSidebarWidth
                        formatSidebarWidth = startingWidth + Double(translation)
                    } onEnded: {
                        formatDragStartWidth = nil
                        storedFormatSidebarWidth = formatSidebarWidth
                    }
                    .padding(.horizontal, 4)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                documentSurface
                    .background(MarkViewDesign.documentSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(MarkViewDesign.strongBorder, lineWidth: 0.8)
                            .allowsHitTesting(false)
                    )
                    .shadow(color: MarkViewDesign.shadow.opacity(0.58), radius: 14, y: 5)

                if showAISidebar {
                    InspectorResizeHandle { translation in
                        if dragStartWidth == nil {
                            dragStartWidth = inspectorWidth
                        }
                        let startingWidth = dragStartWidth ?? inspectorWidth
                        inspectorWidth = startingWidth - Double(translation)
                    } onEnded: {
                        dragStartWidth = nil
                        storedInspectorWidth = inspectorWidth
                    }
                    .padding(.horizontal, 4)
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                    AIAssistantSidebar(
                        aiService: aiService,
                        documentText: $document.text,
                        fileURL: fileURL,
                        fileExtension: fileExtension,
                        externalSelectedText: selectedText,
                        selectionRequest: selectionRequest,
                        onApplyEdit: { updatedText in
                            applyEditWithUndo(updatedText)
                        },
                        onUndoLastEdit: {
                            undoLastEdit()
                        },
                        onNavigateToLocation: { location in
                            navigator.navigateToLocation(
                                location,
                                text: document.text,
                                viewMode: viewMode,
                                reduceMotion: reduceMotion
                            )
                        },
                        onReviewEdit: { proposal in
                            reviewProposal(proposal)
                        }
                    )
                    .frame(width: inspectorWidth)
                    .background(MarkViewDesign.sidebarSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(MarkViewDesign.strongBorder, lineWidth: 0.8)
                            .allowsHitTesting(false)
                    )
                    .shadow(color: MarkViewDesign.shadow.opacity(0.58), radius: 14, y: 5)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                }
            }
            .padding(10)
        }
        .frame(minWidth: 760, minHeight: 520)
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08),
            value: showAISidebar
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08),
            value: showFormatSidebar
        )
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08)) {
                        showFormatSidebar.toggle()
                    }
                } label: {
                    Label(
                        showFormatSidebar ? "Hide Formatting Panel" : "Show Formatting Panel",
                        systemImage: "sidebar.left"
                    )
                }
                .help(showFormatSidebar
                      ? "Hide the formatting panel (⌘⌥F)"
                      : "Show the formatting panel — styles, lists, tables, direction, Persian tools (⌘⌥F)")

                shareButton
            }

            ToolbarItem(placement: .principal) {
                TabSwitcher(selection: Binding(
                    get: { viewMode },
                    set: { viewMode = $0 }
                ))
                    .padding(4)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(MarkViewDesign.strongBorder, lineWidth: 0.7)
                    )
                    .shadow(color: MarkViewDesign.shadow.opacity(0.55), radius: 5, y: 2)
                    .help("Switch between Preview and Source")
            }

            ToolbarItemGroup(placement: .automatic) {
                Button(action: zoomOut) {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .help("Zoom Out (⌘-)")
                .disabled(zoomLevel <= 0.5)

                Button(action: zoomReset) {
                    Text("\(Int(zoomLevel * 100))%")
                        .font(.caption.monospacedDigit())
                }
                .help("Actual Size (⌘0)")
                .buttonStyle(.plain)

                Button(action: zoomIn) {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .help("Zoom In (⌘+)")

                Button(action: reloadDocument) {
                    Label("Reload", systemImage: externalChangeAvailable
                          ? "arrow.clockwise.circle.fill"
                          : "arrow.clockwise")
                }
                .help(externalChangeAvailable
                      ? "This file changed on disk while you had unsaved edits. Reload to take the version on disk and discard yours (⌘R)"
                      : "Reload Document (⌘R)")
                .foregroundStyle(externalChangeAvailable ? Color.orange : Color.primary)

                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08)) {
                        showAISidebar.toggle()
                    }
                } label: {
                    Label("Markowski", systemImage: "sparkles")
                }
                .help("Markowski (⌘⌥A)")
            }
        }
        .background(keyboardShortcuts)
        .background(MarkViewWindowConfigurator())
        .onAppear {
            navigator.updateDocumentText(document.text)
            lastSyncedText = document.text
            schedulePersianScan()
            if let url = fileURL {
                fileWatcher.startWatching(url: url)
            }
        }
        .onChange(of: document.text) { _, newText in
            navigator.updateDocumentText(newText)
            schedulePersianScan()
        }
        .onChange(of: selectedText) { _, _ in
            schedulePersianScan()
        }
        .onChange(of: showFormatSidebar) { _, shown in
            // No point analysing a document while the panel that shows the
            // result is closed.
            if shown { schedulePersianScan() }
        }
        .onChange(of: viewMode) { _, _ in
            tableBridge.clear()
        }

        .onChange(of: fileWatcher.fileDidChange) { _, changed in
            if changed {
                reloadFromDiskIfSafe()
                fileWatcher.resetChangeFlag()
            }
        }
    }

    /// Shares the file itself when it exists on disk, and its text when the
    /// document has never been saved — sharing a nil URL would silently do
    /// nothing.
    @ViewBuilder
    private var shareButton: some View {
        if let fileURL {
            ShareLink(item: fileURL) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share “\(fileURL.lastPathComponent)”")
        } else {
            ShareLink(item: document.text) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Share this document’s text — save the file first to share the file itself")
            .disabled(document.text.isEmpty)
        }
    }

    private var documentSurface: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if viewMode == .editor {
                    // The canvas *is* the document: editing happens here, and
                    // Markdown is only what it is saved as.
                    RichTextCanvas(
                        markdown: $document.text,
                        onSelectionChange: { selection in
                            selectedText = selection
                        },
                        onAssistantRequest: { selection in
                            selectedText = selection
                            selectionRequest = PreviewSelectionRequest(action: .ask, text: selection)
                            if !showAISidebar {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08)) {
                                    showAISidebar = true
                                }
                            }
                        },
                        documentDirectory: fileURL?.deletingLastPathComponent(),
                        tableBridge: tableBridge,
                        onTextViewReady: { textView in
                            navigator.attachCanvas(textView)
                        }
                    )
                    .id(refreshTrigger)
                } else if viewMode == .preview {

                    RendererWebView(
                        content: document.text,
                        fileExtension: fileExtension,
                        documentURL: fileURL,
                        zoomLevel: zoomLevel,
                        onSwitchToSource: {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                                viewMode = .source
                            }
                        },
                        onOpenLocalDocument: { localURL in
                            NSWorkspace.shared.open(localURL)
                        },
                        onTextSelected: { selection in
                            selectedText = selection
                        },
                        onSelectionAction: { action, text in
                            selectedText = text
                            selectionRequest = PreviewSelectionRequest(action: action, text: text)
                            if !showAISidebar {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08)) {
                                    showAISidebar = true
                                }
                            }
                        },
                        onBlockEdited: { range, replacement in
                            applyBlockEdit(range: range, replacement: replacement)
                        },
                        onCopyBlock: { text in
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        },
                        onInsertBlock: { offset, text in
                            applyBlockEdit(range: NSRange(location: offset, length: 0), replacement: text)
                        },
                        onDeleteBlock: { range in
                            applyBlockEdit(range: range, replacement: "")
                        },
                        onExportDiagram: { export in
                            handleDiagramExport(export)
                        },
                        onWebViewReady: { webView in
                            navigator.attachPreview(webView)
                        }
                    )
                    .id(refreshTrigger)
                } else {
                    VStack(spacing: 0) {
                        if let proposal = aiService.activeProposal, proposal.status == .pending {
                            AIDiffView(
                                summary: proposal.summary,
                                originalText: document.text,
                                proposedText: proposal.updatedDocument,
                                onAccept: {
                                    applyEditWithUndo(proposal.updatedDocument)
                                    aiService.markProposalApplied(proposal)
                                },
                                onReject: {
                                    aiService.discardProposal()
                                }
                            )
                            .padding(12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        SourceView(
                            text: $document.text,
                            fontSize: fontSize * zoomLevel,
                            navigator: navigator,
                            onTextSelected: { selection in
                                selectedText = selection
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if navigator.isSearchPresented {
                FindBarView(navigator: navigator, documentText: document.text) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        navigator.isSearchPresented = false
                    }
                }
                .padding(.top, 12)
                .padding(.trailing, 14)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -5)))
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MarkViewDesign.documentSurface)
        .animation(
            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.76, blendDuration: 0.12),
            value: viewMode
        )
    }

    private var keyboardShortcuts: some View {
        ZStack {
            Button("") {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    navigator.isSearchPresented = true
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .hidden()

            Button("") { navigator.nextMatch() }
                .keyboardShortcut("g", modifiers: .command)
                .hidden()

            Button("") { navigator.previousMatch() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .hidden()

            Button("") {
                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08)) {
                    showAISidebar.toggle()
                }
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .hidden()

            Button("") {
                withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08)) {
                    showFormatSidebar.toggle()
                }
            }
            .keyboardShortcut("f", modifiers: [.command, .option])
            .hidden()

            Button("") {
                aiService.startNewChat()
                if !showAISidebar {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84, blendDuration: 0.08)) {
                        showAISidebar = true
                    }
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .hidden()
        }
        .frame(width: 0, height: 0)
    }

    /// The mode actually in use. Mermaid documents have no block model, so the
    /// canvas can't show them — they fall back to the rendered preview rather
    /// than to an empty editor.
    private var viewMode: ViewMode {
        get {
            ViewMode.effective(
                stored: ViewMode(rawValue: storedViewMode) ?? .editor,
                fileExtension: fileExtension
            )
        }
        nonmutating set { storedViewMode = newValue.rawValue }
    }

    private var fileExtension: String {
        fileURL?.pathExtension.lowercased() ?? "md"
    }

    private var inspectorWidth: CGFloat {
        get { CGFloat(min(max(storedInspectorWidth, inspectorMinimumWidth), inspectorMaximumWidth)) }
        nonmutating set { storedInspectorWidth = Double(min(max(newValue, inspectorMinimumWidth), inspectorMaximumWidth)) }
    }

    private var formatSidebarWidth: CGFloat {
        get { CGFloat(min(max(storedFormatSidebarWidth, formatSidebarMinimumWidth), formatSidebarMaximumWidth)) }
        nonmutating set {
            storedFormatSidebarWidth = Double(min(max(newValue, formatSidebarMinimumWidth), formatSidebarMaximumWidth))
        }
    }

    private func zoomIn() {
        withAnimation(.easeOut(duration: 0.12)) { zoomLevel = min(zoomLevel + 0.15, 2.5) }
    }

    private func zoomOut() {
        withAnimation(.easeOut(duration: 0.12)) { zoomLevel = max(zoomLevel - 0.15, 0.5) }
    }

    private func zoomReset() {
        withAnimation(.easeOut(duration: 0.12)) { zoomLevel = 1.0 }
    }

    private func reloadDocument() {
        reloadFromDisk()
        externalChangeAvailable = false
        refreshTrigger = UUID()
    }

    private func reloadFromDisk() {
        guard let url = fileURL else { return }
        do {
            let freshText = try DocumentLoader.loadString(from: url)
            document.text = freshText
            lastSyncedText = freshText
        } catch {
            print("Failed to reload document from disk: \(error)")
        }
    }

    /// Reacts to the file changing on disk.
    ///
    /// Most of these events are our *own* autosave landing, and a few are a
    /// genuine external edit. Adopting disk content unconditionally was unsafe
    /// in both directions: it churned the view on every save, and — because
    /// autosave is deferred — it could read a stale file and overwrite edits
    /// the user had just made. So disk only wins when we have nothing
    /// unsaved of our own.
    private func reloadFromDiskIfSafe() {
        guard let url = fileURL,
              let freshText = try? DocumentLoader.loadString(from: url) else { return }

        guard freshText != document.text else {
            // Our own write coming back to us.
            lastSyncedText = freshText
            return
        }

        guard document.text == lastSyncedText else {
            // Both sides moved. The user's unsaved work is the thing that
            // cannot be recovered, so it stays; Reload (⌘R) takes disk.
            externalChangeAvailable = true
            return
        }

        document.text = freshText
        lastSyncedText = freshText
    }

    // MARK: - Images

    /// Brings a picture into the document.
    ///
    /// The reference is written relative to the document whenever the file
    /// lives beside it, so the folder stays portable — moving or sharing the
    /// document takes its images along. A file from elsewhere is offered a copy
    /// next to the document for the same reason, and is otherwise linked by
    /// absolute path.
    private func insertImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose an image"
        panel.message = "The image will be placed at the caret."
        panel.allowedContentTypes = ImageAttachmentLoader.supportedTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let markdown = panel.urls
            .map { url in "![\(url.deletingPathExtension().lastPathComponent)](\(imageReference(for: url)))" }
            .joined(separator: "\n\n")

        if viewMode == .editor, let canvas = navigator.canvasTextView as? CanvasTextView {
            canvas.insertImageBlocks(markdown)
            return
        }

        let range = viewMode == .source
            ? (navigator.sourceTextView?.selectedRange() ?? NSRange(location: 0, length: 0))
            : NSRange(location: (document.text as NSString).length, length: 0)
        let edit = MarkdownFormatter.insertBlock(document.text, range: range, block: markdown)
        applyEditWithUndo(edit.text)
    }

    /// The path to write into the Markdown for an image.
    private func imageReference(for url: URL) -> String {
        guard let directory = fileURL?.deletingLastPathComponent() else {
            return url.path
        }

        let base = directory.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        if target.hasPrefix(base.hasSuffix("/") ? base : base + "/") {
            return String(target.dropFirst(base.count + (base.hasSuffix("/") ? 0 : 1)))
        }

        // Outside the document's folder: offer to bring a copy along, since a
        // path into someone's Downloads folder stops working the moment the
        // document is shared or the file is tidied away.
        let alert = NSAlert()
        alert.messageText = "Copy “\(url.lastPathComponent)” next to your document?"
        alert.informativeText = """
        The image is somewhere else on your Mac. Copying it beside the document keeps the link working if you move or share the document.
        """
        alert.addButton(withTitle: "Copy Alongside")
        alert.addButton(withTitle: "Link Where It Is")

        guard alert.runModal() == .alertFirstButtonReturn else { return url.path }

        let destination = uniqueDestination(for: url, in: directory)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination.lastPathComponent
        } catch {
            return url.path
        }
    }

    /// A name in `directory` that isn't taken, so copying never overwrites.
    private func uniqueDestination(for url: URL, in directory: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var candidate = directory.appendingPathComponent(url.lastPathComponent)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }

    // MARK: - Diagrams

    /// Puts a rendered diagram on the pasteboard, or writes it to a file the
    /// user picks.
    private func handleDiagramExport(_ export: DiagramExport) {
        switch export.destination {
        case .copy:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            switch export.format {
            case .png:
                // Both the image and the raw PNG go on: some apps paste an
                // NSImage, others look for the file type.
                if let image = NSImage(data: export.data) {
                    pasteboard.writeObjects([image])
                }
                pasteboard.setData(export.data, forType: .png)
            case .svg:
                pasteboard.setString(
                    String(data: export.data, encoding: .utf8) ?? "",
                    forType: .string
                )
            }

        case .save:
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = suggestedDiagramName(for: export.format)
            panel.allowedContentTypes = export.format == .png ? [.png] : [.svg]
            panel.message = export.format == .png
                ? "Save this diagram as a PNG image."
                : "Save this diagram as an SVG, which stays sharp at any size."

            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try export.data.write(to: url, options: .atomic)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Couldn’t save the diagram"
                alert.runModal()
            }
        }
    }

    /// Names the file after the document it came from, so a folder of exports
    /// stays legible.
    private func suggestedDiagramName(for format: DiagramExport.Format) -> String {
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "Diagram"
        return "\(base) diagram.\(format.fileExtension)"
    }

    private func reviewProposal(_ proposal: AIEditProposal) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            viewMode = .source
        }
        let firstChangedLine = DiffEngine.firstChangedLine(original: document.text, modified: proposal.updatedDocument)
        navigator.scrollSourceToLine(firstChangedLine)
    }

    /// Splices a block edited in the preview back into the source. The range
    /// comes from the renderer, which derived it from the same string this is
    /// applied to — but the file can change underneath (reload, AI edit), so
    /// the range is validated before it is trusted with a write.
    private func applyBlockEdit(range: NSRange, replacement: String) {
        let source = document.text as NSString
        guard range.location >= 0,
              range.length >= 0,
              range.upperBound <= source.length else {
            return
        }

        let updated = source.replacingCharacters(in: range, with: replacement)
        guard updated != document.text else { return }
        applyEditWithUndo(updated)
    }

    // MARK: - Formatting

    /// Where a formatting command applies. In Source mode that's the live caret
    /// or selection; in Preview mode the preview reports the selected string,
    /// which is matched back to a source range.
    private var currentEditRange: NSRange {
        currentSelection.range
    }

    /// A resolved selection, and whether it is real. A selection the user made
    /// but that couldn't be located in the source must not quietly become
    /// "offset 0" — that applied the command somewhere they weren't looking,
    /// which is why Preview-mode formatting appeared to do nothing.
    private var currentSelection: (range: NSRange, isUnresolved: Bool) {
        if viewMode == .source, let textView = navigator.sourceTextView {
            return (textView.selectedRange(), false)
        }

        guard let selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (NSRange(location: 0, length: 0), false)
        }

        if let resolved = SourceSelectionResolver.range(of: selectedText, in: document.text) {
            return (resolved, false)
        }
        return (NSRange(location: 0, length: 0), true)
    }

    /// The text a command would act on — the selection, or the whole document
    /// when there is none.
    private var currentScopeText: String {
        let range = currentEditRange
        guard range.length > 0 else { return document.text }
        return (document.text as NSString).substring(with: range)
    }

    /// The table the user is in, from whichever surface they're editing on.
    /// The canvas wins: if a grid holds focus, that is unambiguously the table
    /// they mean.
    private var currentTableContext: TableEditingContext? {
        if let live = tableBridge.context {
            return live
        }
        return MarkdownFormatter.tableContext(in: document.text, at: currentEditRange.location)?
            .editingContext
    }

    /// The inline style a sidebar marker maps to on the canvas, for commands
    /// the editor can apply natively.
    private static func canvasInlineStyle(for marker: String) -> InlineStyle? {
        switch marker {
        case "**": return .bold
        case "*": return .italic
        case "~~": return .strikethrough
        case "`": return .code
        case "==": return .highlight
        default: return nil
        }
    }

    /// The Persian text transform a command maps to, when it has one.
    private static func persianTransform(for command: FormatCommand) -> ((String) -> String)? {
        switch command {
        case .persianFixAll: return PersianTextTools.fixAll
        case .persianNormalizeLetters: return PersianTextTools.normalizeLetters
        case .persianZWNJ: return PersianTextTools.applyZeroWidthNonJoiner
        case .persianPunctuation: return PersianTextTools.normalizePunctuation
        case .persianTidyWhitespace: return PersianTextTools.tidyWhitespace
        case .persianDigits(let persian):
            return persian ? PersianTextTools.toPersianDigits : PersianTextTools.toLatinDigits
        case .pinDirection(let rightToLeft):
            return { PersianTextTools.pinDirection($0, rightToLeft: rightToLeft) }
        default:
            return nil
        }
    }

    /// Handles a command on the live canvas, where the document itself is the
    /// editing surface. Returns false when the command should instead run
    /// through the Markdown source (Source mode, or whole-document rewrites).
    private func applyCanvasCommand(_ command: FormatCommand, canvas: CanvasTextView) -> Bool {
        switch command {
        case .inline(let marker):
            guard let style = Self.canvasInlineStyle(for: marker) else { return false }
            guard canvas.selectedRange().length > 0 else {
                showFormatNotice("Select some text first — inline styles apply to the selection.")
                return true
            }
            canvas.toggleInlineStyle(style)
            return true

        case .heading(let level):
            if !canvas.setHeadingLevel(level) {
                showFormatNotice("Text styles apply to paragraphs and headings — lists, code, and tables keep their own structure.")
            }
            return true

        case .linePrefix("- "):
            canvas.toggleList(ordered: false, checkbox: false)
            return true
        case .linePrefix("- [ ] "):
            canvas.toggleList(ordered: false, checkbox: true)
            return true
        case .linePrefix("> "):
            canvas.toggleQuote()
            return true
        case .orderedList:
            canvas.toggleList(ordered: true, checkbox: false)
            return true

        case .codeFence:
            canvas.toggleCodeBlock()
            return true
        case .horizontalRule:
            canvas.insertDivider()
            return true
        case .table(let rows, let columns):
            canvas.insertTable(rows: rows, columns: columns)
            return true
        case .link:
            canvas.promptForLink()
            return true
        case .image:
            insertImage()
            return true
        case .direction(let direction):
            canvas.setBlockDirection(rightToLeft: direction == .rightToLeft)
            return true

        case .pinDirection:
            guard canvas.selectedRange().length > 0 else {
                showFormatNotice("Select the text to pin first.")
                return true
            }
            fallthrough
        case .persianFixAll, .persianNormalizeLetters, .persianZWNJ, .persianPunctuation,
             .persianTidyWhitespace, .persianDigits:
            guard let transform = Self.persianTransform(for: command) else { return false }
            // With a selection the rewrite happens in place on the canvas;
            // with none it applies to the whole document via the source path.
            guard canvas.selectedRange().length > 0 else { return false }
            if !canvas.rewriteSelection(transform) {
                showFormatNotice("Nothing to change in the selection.")
            }
            return true

        default:
            return false
        }
    }

    private func applyFormatCommand(_ command: FormatCommand) {
        // In the editor the canvas *is* the document, so commands are applied
        // to it directly instead of round-tripping through the Markdown
        // source. That keeps the selection and the scroll where they are — and
        // unlike matching the selected string against the source, it always
        // hits the block and the occurrence the user actually selected.
        if viewMode == .editor, let canvas = navigator.canvasTextView as? CanvasTextView,
           applyCanvasCommand(command, canvas: canvas) {
            return
        }

        let text = document.text
        let selection = currentSelection

        guard !selection.isUnresolved else {
            showFormatNotice("Couldn’t locate that selection in the Markdown source. Try selecting whole words, or switch to Source.")
            return
        }
        let range = selection.range

        let edit: MarkdownEdit?
        switch command {
        case .heading(let level):
            edit = MarkdownFormatter.setHeading(text, range: range, level: level)
        case .inline(let marker):
            edit = MarkdownFormatter.toggleInline(text, range: range, marker: marker)
        case .linePrefix(let prefix):
            edit = MarkdownFormatter.toggleLinePrefix(text, range: range, prefix: prefix)
        case .orderedList:
            edit = MarkdownFormatter.toggleOrderedList(text, range: range)
        case .link:
            edit = MarkdownFormatter.insertLink(text, range: range)
        case .image:
            insertImage()
            return
        case .codeFence:
            edit = MarkdownFormatter.insertCodeFence(text, range: range)
        case .horizontalRule:
            edit = MarkdownFormatter.insertHorizontalRule(text, range: range)
        case .table(let rows, let columns):
            edit = MarkdownFormatter.insertTable(text, range: range, rows: rows, columns: columns)
        case .direction(let direction):
            edit = MarkdownFormatter.setBlockDirection(text, range: range, direction: direction)

        case .tableAddRow:
            if tableBridge.apply(.addRow) { return }
            edit = MarkdownFormatter.addTableRow(text, at: range.location)
        case .tableAddColumn:
            if tableBridge.apply(.addColumn) { return }
            edit = MarkdownFormatter.addTableColumn(text, at: range.location)
        case .tableDeleteRow:
            if tableBridge.apply(.deleteRow) { return }
            edit = MarkdownFormatter.deleteTableRow(text, at: range.location)
        case .tableDeleteColumn:
            if tableBridge.apply(.deleteColumn) { return }
            edit = MarkdownFormatter.deleteTableColumn(text, at: range.location)
        case .tableAlign(let alignment):
            if tableBridge.apply(.setAlignment(alignment)) { return }
            edit = MarkdownFormatter.setTableColumnAlignment(
                text, at: range.location, alignment: alignment.formatterAlignment
            )

        // Cell-level commands exist only where a live grid does. Markdown text
        // has no way to express them, so in Source mode they say so rather
        // than quietly doing something else.
        case .tableCellAlign(let alignment):
            if !tableBridge.apply(.setCellAlignment(alignment)) {
                showFormatNotice("Put the caret in a table cell in Editor mode to align just that cell.")
            }
            return
        case .tableCellVerticalAlign(let alignment):
            if !tableBridge.apply(.setCellVerticalAlignment(alignment)) {
                showFormatNotice("Put the caret in a table cell in Editor mode to set its vertical position.")
            }
            return
        case .tableMergeRight:
            if !tableBridge.apply(.mergeRight) {
                showFormatNotice("There’s no cell to the right to merge with.")
            }
            return
        case .tableMergeDown:
            if !tableBridge.apply(.mergeDown) {
                showFormatNotice("There’s no cell below to merge with.")
            }
            return
        case .tableUnmerge:
            if !tableBridge.apply(.unmerge) {
                showFormatNotice("This cell isn’t merged.")
            }
            return

        case .persianFixAll:
            edit = rewriteScope(text, range: range, PersianTextTools.fixAll)
        case .persianNormalizeLetters:
            edit = rewriteScope(text, range: range, PersianTextTools.normalizeLetters)
        case .persianZWNJ:
            edit = rewriteScope(text, range: range, PersianTextTools.applyZeroWidthNonJoiner)
        case .persianPunctuation:
            edit = rewriteScope(text, range: range, PersianTextTools.normalizePunctuation)
        case .persianTidyWhitespace:
            edit = rewriteScope(text, range: range, PersianTextTools.tidyWhitespace)
        case .persianDigits(let persian):
            // Digits inside code are part of the code, not the prose.
            edit = rewriteScope(text, range: range) { scope in
                PersianTextTools.outsideCode(scope) {
                    persian ? PersianTextTools.toPersianDigits($0) : PersianTextTools.toLatinDigits($0)
                }
            }
        case .pinDirection(let rightToLeft):
            guard range.length > 0 else { return }
            edit = rewriteScope(text, range: range) {
                PersianTextTools.pinDirection($0, rightToLeft: rightToLeft)
            }
        }

        guard let edit else {
            showFormatNotice("That action needs the caret inside a table.")
            return
        }
        guard edit.text != text else {
            showFormatNotice("Nothing to change here.")
            return
        }
        applyEditWithUndo(edit.text)

        // Keep the user where they were working.
        if let textView = navigator.sourceTextView {
            let length = (edit.text as NSString).length
            let safe = NSRange(
                location: min(edit.selectedRange.location, length),
                length: min(edit.selectedRange.length, max(0, length - min(edit.selectedRange.location, length)))
            )
            textView.setSelectedRange(safe)
        }
    }

    /// Re-analyses the Persian text after a short pause.
    ///
    /// Debounced because this runs on every keystroke, and scanning a long
    /// document each time would make typing stutter for exactly the users this
    /// feature is for.
    private func schedulePersianScan() {
        guard showFormatSidebar else { return }
        let token = UUID()
        persianScanToken = token
        let scope = currentScopeText

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard persianScanToken == token else { return }

            let issues = PersianTextAnalyzer.analyze(scope)
            let digits = PersianTextTools.digitCounts(in: scope)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                persianIssues = issues
                persianDigitCounts = digits
            }
        }
    }

    /// A short-lived line in the panel. A formatting command that can't do
    /// anything should say so rather than look broken.
    private func showFormatNotice(_ message: String) {
        formatNotice = message
        let token = UUID()
        formatNoticeToken = token

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard formatNoticeToken == token else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                formatNotice = nil
            }
        }
    }

    /// Applies a whole-string transform to the selection, or to the entire
    /// document when nothing is selected.
    private func rewriteScope(
        _ text: String,
        range: NSRange,
        _ transform: (String) -> String
    ) -> MarkdownEdit {
        let source = text as NSString
        guard range.length > 0 else {
            let rewritten = transform(text)
            return MarkdownEdit(
                text: rewritten,
                selectedRange: NSRange(location: 0, length: 0)
            )
        }

        let rewritten = transform(source.substring(with: range))
        return MarkdownEdit(
            text: source.replacingCharacters(in: range, with: rewritten),
            selectedRange: NSRange(location: range.location, length: (rewritten as NSString).length)
        )
    }

    private func applyEditWithUndo(_ newText: String) {
        let oldText = document.text
        if let manager = undoManager {
            manager.registerUndo(withTarget: manager) { _ in
                self.applyEditWithUndo(oldText)
            }
        }

        // No `refreshTrigger` here: the canvas and the preview both react to
        // the text binding on their own. Regenerating the trigger tore the
        // whole view down and threw the scroll position back to the top.
        //
        // And no direct write to disk: `DocumentGroup` owns this file and
        // autosaves it. Writing behind its back changed the modification date
        // it tracks, so the next autosave reported the file as "changed by
        // another application" and demanded Save Anyway / Revert.
        document.text = newText
    }

    private func undoLastEdit() {
        guard undoManager?.canUndo == true else { return }
        undoManager?.undo()
    }
}

private struct InspectorResizeHandle: View {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    @State private var isHovered = false
    @State private var isDragging = false

    var body: some View {
        Color.clear
            .frame(width: 12)
            .overlay(alignment: .center) {
                Capsule()
                    .fill(Color.white.opacity(isDragging ? 0.98 : 0.86))
                    .frame(width: isDragging ? 6 : 5, height: isDragging ? 52 : 44)
                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.16), lineWidth: 0.6))
                    .shadow(color: Color.black.opacity(0.34), radius: 5, y: 2)
                    .scaleEffect(isHovered || isDragging ? 1 : 0.72)
                    .opacity(isHovered || isDragging ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        isDragging = true
                        onChanged(value.translation.width)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEnded()
                    }
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isHovered)
            .animation(.spring(response: 0.22, dampingFraction: 0.76), value: isDragging)
            .onHover { isHovered = $0 }
            .help("Resize AI Inspector")
            .accessibilityLabel("Resize AI Inspector")
    }
}

private struct MarkViewWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            configure(window)
        } else {
            DispatchQueue.main.async {
                if let window = nsView.window {
                    configure(window)
                }
            }
        }
    }

    private func configure(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        window.toolbar?.showsBaselineSeparator = false
    }
}

struct TabSwitcher: View {
    @Binding var selection: ViewMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let segmentWidth: CGFloat = 72

    private var selectedIndex: Int {
        ViewMode.allCases.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.16)
                        : Color(nsColor: .controlBackgroundColor)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.20)
                                : MarkViewDesign.strongBorder.opacity(0.62),
                            lineWidth: 0.7
                        )
                )
                .shadow(
                    color: colorScheme == .dark ? .black.opacity(0.34) : MarkViewDesign.shadow.opacity(0.45),
                    radius: 3,
                    y: 1
                )
                .frame(width: segmentWidth, height: 28)
                .offset(x: CGFloat(selectedIndex) * segmentWidth)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.72, blendDuration: 0.1),
                    value: selection
                )

            HStack(spacing: 0) {
                ForEach(ViewMode.allCases) { mode in
                    Button {
                        guard selection != mode else { return }
                        withAnimation(
                            reduceMotion
                                ? nil
                                : .spring(response: 0.36, dampingFraction: 0.72, blendDuration: 0.1)
                        ) {
                            selection = mode
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: selection == mode ? .semibold : .medium))
                            .foregroundStyle(Color.primary.opacity(selection == mode ? 1.0 : 0.86))
                            .frame(width: segmentWidth, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == mode ? .isSelected : [])
                }
            }
        }
        .frame(width: segmentWidth * CGFloat(ViewMode.allCases.count), height: 28)
        .accessibilityElement(children: .contain)
    }
}

private struct MarkViewMaterialBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}
