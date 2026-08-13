import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// What the floating bar over a preview selection was asked to do.
enum PreviewSelectionAction: String {
    case ask
    case explain
    case improve
}

/// Serves local files — the images a document refers to — into the preview.
///
/// The preview page is loaded from the app bundle with read access to the
/// bundle alone, which is what a `file:` page is confined to. That confinement
/// is why an `![](diagram.png)` sitting next to the user's document never
/// appeared: the web view was not allowed to open it, so every local image in
/// every document silently rendered as a broken image. Reading the file on this
/// side and handing back the bytes sidesteps the confinement without widening
/// what the page itself may reach.
final class LocalResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mvlocal"

    /// The folder the open document lives in; relative paths resolve here.
    var documentDirectory: URL?

    enum HandlerError: LocalizedError {
        case notFound

        var errorDescription: String? { "That file could not be read." }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let resolved = resolve(url),
              let data = try? Data(contentsOf: resolved) else {
            urlSchemeTask.didFailWithError(HandlerError.notFound)
            return
        }

        let mimeType = UTType(filenameExtension: resolved.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        let response = URLResponse(
            url: url,
            mimeType: mimeType,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    /// Turns `mvlocal://doc/?p=<path>` into a file on disk.
    ///
    /// Only images resolve. A document is data, not a trusted script, and
    /// serving whatever path it happens to name would let one reach for files
    /// that have nothing to do with rendering it.
    func resolve(_ url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "p" })?.value,
              !raw.isEmpty else {
            return nil
        }

        let expanded = (raw as NSString).expandingTildeInPath
        let candidate: URL
        if expanded.hasPrefix("/") {
            candidate = URL(fileURLWithPath: expanded)
        } else if let directory = documentDirectory {
            candidate = directory.appendingPathComponent(expanded)
        } else {
            return nil
        }

        let standardized = candidate.standardizedFileURL
        guard ImageAttachmentLoader.isSupported(url: standardized),
              FileManager.default.fileExists(atPath: standardized.path) else {
            return nil
        }
        return standardized
    }
}

/// A diagram leaving the app, as the renderer described it.
struct DiagramExport {
    enum Format: String {
        case png
        case svg

        var fileExtension: String { rawValue }
    }

    enum Destination: String {
        case copy
        case save
    }

    let format: Format
    let destination: Destination
    /// PNG bytes, or the SVG markup encoded as UTF-8.
    let data: Data
}

/// One press of that bar. The `id` makes repeated presses of the same action on
/// the same text distinct events rather than a no-op state change.
struct PreviewSelectionRequest: Equatable {
    let id: UUID
    let action: PreviewSelectionAction
    let text: String

    init(id: UUID = UUID(), action: PreviewSelectionAction, text: String) {
        self.id = id
        self.action = action
        self.text = text
    }
}

struct RendererWebView: NSViewRepresentable {
    let content: String
    let fileExtension: String
    let documentURL: URL?
    let zoomLevel: Double
    let onSwitchToSource: () -> Void
    let onOpenLocalDocument: (URL) -> Void
    var onTextSelected: ((String?) -> Void)? = nil
    var onSelectionAction: ((PreviewSelectionAction, String) -> Void)? = nil
    /// A block edited in place in the preview, as a source range plus its
    /// replacement text.
    var onBlockEdited: ((NSRange, String) -> Void)? = nil
    /// A block copied from the preview, already in the form the user asked for.
    var onCopyBlock: ((String) -> Void)? = nil
    /// A new block chosen from an insertion point, as an offset and its text.
    var onInsertBlock: ((Int, String) -> Void)? = nil
    /// A block removed from the preview, as the source range to cut.
    var onDeleteBlock: ((NSRange) -> Void)? = nil
    /// A rendered diagram the user asked to take out of the app.
    var onExportDiagram: ((DiagramExport) -> Void)? = nil
    var onWebViewReady: ((WKWebView) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        userContentController.add(context.coordinator, name: "markview")
        configuration.userContentController = userContentController

        // Restrict navigation and enable developer options if needed
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        // Has to be installed on the configuration before the web view exists.
        context.coordinator.localResources.documentDirectory =
            documentURL?.deletingLastPathComponent()
        configuration.setURLSchemeHandler(
            context.coordinator.localResources,
            forURLScheme: LocalResourceSchemeHandler.scheme
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background until loaded
        webView.allowsMagnification = true // Enable pinch-to-zoom
        onWebViewReady?(webView)

        // Load html template
        if let bundleHTML = Bundle.main.url(forResource: "renderer", withExtension: "html") {
            // Always allow read access to the bundle's resource folder so CSS and JS can load
            let readAccessURL = bundleHTML.deletingLastPathComponent()
            webView.loadFileURL(bundleHTML, allowingReadAccessTo: readAccessURL)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.localResources.documentDirectory =
            documentURL?.deletingLastPathComponent()

        guard !context.coordinator.isLoadingHTML else {
            // HTML is still initial loading; defer update
            context.coordinator.pendingRender = { [weak webView, weak coordinator = context.coordinator] in
                guard let webView, let coordinator else { return }
                self.performRender(in: webView, coordinator: coordinator)
            }
            return
        }

        performRender(in: webView, coordinator: context.coordinator)
    }

    private func performRender(in webView: WKWebView, coordinator: Coordinator) {
        let isDark = colorScheme == .dark
        let ext = fileExtension.lowercased()

        // `renderDocument` replaces `#content.innerHTML` wholesale, which
        // destroys the user's text selection and their scroll position.
        // SwiftUI calls `updateNSView` on *every* re-evaluation of the parent
        // — including the one caused by recording that very selection — so
        // re-rendering unconditionally meant a selection could never survive
        // being made. Only re-render when the rendered inputs actually changed.
        let needsRender = coordinator.lastRenderedContent != content
            || coordinator.lastRenderedExtension != ext
            || coordinator.lastRenderedIsDark != isDark

        if needsRender {
            // Escape JSON content for safe JS evaluation
            guard let jsonData = try? JSONSerialization.data(withJSONObject: [content], options: []),
                  let jsonString = String(data: jsonData, encoding: .utf8),
                  jsonString.count >= 2 else {
                return
            }

            // Extract raw escaped string without outer array brackets
            let escapedContent = String(jsonString.dropFirst().dropLast())

            let script = """
            if (typeof renderDocument === 'function') {
                renderDocument(\(escapedContent), "\(ext)", \(isDark));
            }
            """

            webView.evaluateJavaScript(script, completionHandler: nil)
            coordinator.lastRenderedContent = content
            coordinator.lastRenderedExtension = ext
            coordinator.lastRenderedIsDark = isDark
        }

        // Zoom is a cheap CSS change and must not force a re-render.
        if coordinator.lastRenderedZoom != zoomLevel {
            webView.evaluateJavaScript("if (typeof setZoom === 'function') { setZoom(\(zoomLevel)); }", completionHandler: nil)
            coordinator.lastRenderedZoom = zoomLevel
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: RendererWebView
        var isLoadingHTML = true
        var pendingRender: (() -> Void)?

        var lastRenderedContent: String?
        var lastRenderedExtension: String?
        var lastRenderedIsDark: Bool?
        var lastRenderedZoom: Double?
        /// Serves the document's own images into the page.
        let localResources = LocalResourceSchemeHandler()

        init(_ parent: RendererWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoadingHTML = false
            // A fresh page has no rendered content, whatever was last sent to
            // the previous one.
            lastRenderedContent = nil
            lastRenderedExtension = nil
            lastRenderedIsDark = nil
            lastRenderedZoom = nil

            parent.onWebViewReady?(webView)
            if let pending = pendingRender {
                pending()
                pendingRender = nil
            } else {
                parent.performRender(in: webView, coordinator: self)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "markview",
               let body = message.body as? [String: Any],
               let action = body["action"] as? String {
                if action == "switchToSource" {
                    DispatchQueue.main.async {
                        self.parent.onSwitchToSource()
                    }
                } else if action == "selectionChanged", let text = body["text"] as? String {
                    // Only a real selection is reported. The renderer used to
                    // post every collapse too, so clicking into the chat — which
                    // drops the web view's selection — silently threw away the
                    // context the user had just picked.
                    guard !text.isEmpty else { return }
                    DispatchQueue.main.async {
                        self.parent.onTextSelected?(text)
                    }
                } else if action == "blockEdited",
                          let start = body["start"] as? Int,
                          let length = body["length"] as? Int,
                          let replacement = body["text"] as? String {
                    DispatchQueue.main.async {
                        self.parent.onBlockEdited?(NSRange(location: start, length: length), replacement)
                    }
                } else if action == "copyBlock", let text = body["text"] as? String, !text.isEmpty {
                    DispatchQueue.main.async {
                        self.parent.onCopyBlock?(text)
                    }
                } else if action == "insertBlock",
                          let at = body["at"] as? Int,
                          let text = body["text"] as? String {
                    DispatchQueue.main.async {
                        self.parent.onInsertBlock?(at, text)
                    }
                } else if action == "deleteBlock",
                          let start = body["start"] as? Int,
                          let length = body["length"] as? Int {
                    DispatchQueue.main.async {
                        self.parent.onDeleteBlock?(NSRange(location: start, length: length))
                    }
                } else if action == "exportDiagram",
                          let rawFormat = body["format"] as? String,
                          let format = DiagramExport.Format(rawValue: rawFormat),
                          let rawDestination = body["mode"] as? String,
                          let destination = DiagramExport.Destination(rawValue: rawDestination) {
                    let payload: Data?
                    switch format {
                    case .png:
                        payload = (body["data"] as? String).flatMap { Data(base64Encoded: $0) }
                    case .svg:
                        payload = (body["text"] as? String)?.data(using: .utf8)
                    }
                    if let payload, !payload.isEmpty {
                        DispatchQueue.main.async {
                            self.parent.onExportDiagram?(DiagramExport(
                                format: format,
                                destination: destination,
                                data: payload
                            ))
                        }
                    }
                } else if action == "selectionAction",
                          let kind = body["kind"] as? String,
                          let selectionAction = PreviewSelectionAction(rawValue: kind),
                          let text = body["text"] as? String,
                          !text.isEmpty {
                    DispatchQueue.main.async {
                        self.parent.onSelectionAction?(selectionAction, text)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                decisionHandler(.cancel)
                
                if url.scheme == "http" || url.scheme == "https" {
                    NSWorkspace.shared.open(url)
                } else if url.isFileURL {
                    let ext = url.pathExtension.lowercased()
                    if ["md", "markdown", "mmd"].contains(ext) {
                        DispatchQueue.main.async {
                            self.parent.onOpenLocalDocument(url)
                        }
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                } else if let docURL = parent.documentURL {
                    // Relative link resolution
                    let resolvedURL = docURL.deletingLastPathComponent().appendingPathComponent(url.path)
                    if FileManager.default.fileExists(atPath: resolvedURL.path) {
                        DispatchQueue.main.async {
                            self.parent.onOpenLocalDocument(resolvedURL)
                        }
                    }
                }
                return
            }

            decisionHandler(.allow)
        }
    }
}
