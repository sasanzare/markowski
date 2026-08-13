import AppKit
import Foundation
import SwiftUI
import WebKit

struct SearchMatch: Identifiable, Equatable {
    let id = UUID()
    let lineNumber: Int
    let lineText: String
    let range: NSRange
}

@MainActor
final class PreviewBridge {
    weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func scrollToBlock(_ blockID: String, reduceMotion: Bool) {
        evaluate("scrollToBlock(\(json(blockID)), \(reduceMotion ? "true" : "false"));")
    }

    func highlightSearchMatches(query: String, currentIndex: Int) {
        evaluate("highlightSearchMatches(\(json(query)), \(currentIndex));")
    }

    func setCurrentSearchMatch(_ index: Int) {
        evaluate("setCurrentSearchMatch(\(index));")
    }

    func clearSearch() {
        evaluate("clearSearchHighlights();")
    }

    func find(_ query: String) {
        evaluate("findText(\(json(query)));" )
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func json(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return String(encoded.dropFirst().dropLast())
    }
}

@MainActor
final class DocumentNavigator: ObservableObject {
    @Published var documentIndex = DocumentIndex()
    @Published var searchQuery = ""
    @Published var searchMatches: [SearchMatch] = []
    @Published var selectedMatchIndex: Int?
    @Published var isSearchPresented = false

    let previewBridge = PreviewBridge()
    weak var webView: WKWebView?
    weak var sourceTextView: NSTextView?
    /// The WYSIWYG canvas, when it is the active surface. It holds rendered
    /// text rather than Markdown, so it is located by text rather than by
    /// source line number.
    weak var canvasTextView: NSTextView?
    private var pendingSourceLine: Int?

    func attachCanvas(_ textView: NSTextView) {
        canvasTextView = textView
    }

    func attachPreview(_ webView: WKWebView) {
        self.webView = webView
        previewBridge.attach(webView)
        if !searchQuery.isEmpty {
            previewBridge.highlightSearchMatches(query: searchQuery, currentIndex: selectedMatchIndex ?? 0)
        }
    }

    func updateDocumentText(_ text: String) {
        documentIndex.buildIndex(from: text)
        if isSearchPresented && !searchQuery.isEmpty {
            performSearch(query: searchQuery, in: text)
        }
    }

    // MARK: - Shared document navigation

    func navigateToLocation(_ location: DocumentLocation, text: String, viewMode: ViewMode, reduceMotion: Bool) {
        let block = documentIndex.resolveLocation(location)

        switch viewMode {
        case .preview:
            // The renderer numbers `block-N` over rendered DOM children while
            // `DocumentIndex` numbers them over source paragraphs, so the two
            // ID spaces disagree. Locate by text, which is stable across both,
            // and only use an ID the renderer itself produced.
            if let quote = location.quote, !quote.isEmpty {
                previewBridge.find(quote)
            } else if let heading = location.heading, !heading.isEmpty {
                previewBridge.find(heading)
            } else if let blockID = location.blockId {
                previewBridge.scrollToBlock(blockID, reduceMotion: reduceMotion)
            } else if let firstLine = block?.contentText
                .components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                previewBridge.find(firstLine.trimmingCharacters(in: .whitespaces))
            }

        case .editor:
            // The canvas shows rendered text — there is no `## ` in it — so a
            // source line number means nothing here. Find the words instead.
            let needles = [location.quote, location.heading, block?.contentText]
                .compactMap { $0 }
                .flatMap { DocumentIndex.quoteCandidates(for: $0) }
            revealInCanvas(needles)

        case .source:
            let targetLine = block?.lineRange.lowerBound ?? location.startLine ?? 1
            scrollSourceToLine(targetLine)
        }
    }

    /// Selects the first candidate that is actually present in the canvas.
    private func revealInCanvas(_ candidates: [String]) {
        guard let textView = canvasTextView else { return }
        let haystack = textView.string as NSString

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }

            let range = haystack.range(of: trimmed, options: [.caseInsensitive])
            guard range.location != NSNotFound else { continue }

            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
            return
        }
    }

    func scrollSourceToLine(_ lineNumber: Int) {
        guard let textView = sourceTextView else {
            pendingSourceLine = max(1, lineNumber)
            return
        }
        scrollSource(textView: textView, toLine: lineNumber)
    }

    func sourceViewReady() {
        guard let pendingSourceLine else { return }
        self.pendingSourceLine = nil
        scrollSourceToLine(pendingSourceLine)
    }

    private func scrollSource(textView: NSTextView, toLine lineNumber: Int) {
        let string = textView.string as NSString
        var currentLine = 1
        var targetIndex = 0

        string.enumerateSubstrings(
            in: NSRange(location: 0, length: string.length),
            options: [.byLines, .substringNotRequired]
        ) { _, range, _, stop in
            if currentLine == lineNumber {
                targetIndex = range.location
                stop.pointee = true
            }
            currentLine += 1
        }

        let targetRange = NSRange(location: targetIndex, length: 0)
        textView.setSelectedRange(targetRange)
        textView.scrollRangeToVisible(targetRange)
        textView.showFindIndicator(for: targetRange)
    }

    // MARK: - Search

    func performSearch(query: String, in text: String) {
        searchQuery = query
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            searchMatches = []
            selectedMatchIndex = nil
            previewBridge.clearSearch()
            return
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let expression = try? NSRegularExpression(
            pattern: NSRegularExpression.escapedPattern(for: normalizedQuery),
            options: [.caseInsensitive]
        )

        var matches: [SearchMatch] = []
        expression?.enumerateMatches(in: text, options: [], range: fullRange) { result, _, _ in
            guard let range = result?.range else { return }
            let lineNumber = lineNumber(for: range.location, in: nsText)
            matches.append(SearchMatch(
                lineNumber: lineNumber,
                lineText: nsText.substring(with: range),
                range: range
            ))
        }

        searchMatches = matches
        selectedMatchIndex = matches.isEmpty ? nil : min(selectedMatchIndex ?? 0, matches.count - 1)
        previewBridge.highlightSearchMatches(query: normalizedQuery, currentIndex: selectedMatchIndex ?? 0)
        if !matches.isEmpty {
            highlightCurrentMatch()
        }
    }

    func nextMatch() {
        guard !searchMatches.isEmpty else { return }
        let current = selectedMatchIndex ?? 0
        selectedMatchIndex = (current + 1) % searchMatches.count
        highlightCurrentMatch()
    }

    func previousMatch() {
        guard !searchMatches.isEmpty else { return }
        let current = selectedMatchIndex ?? 0
        selectedMatchIndex = (current - 1 + searchMatches.count) % searchMatches.count
        highlightCurrentMatch()
    }

    private func highlightCurrentMatch() {
        guard let index = selectedMatchIndex, searchMatches.indices.contains(index) else { return }
        let match = searchMatches[index]

        if let textView = sourceTextView {
            textView.setSelectedRange(match.range)
            textView.scrollRangeToVisible(match.range)
            textView.showFindIndicator(for: match.range)
        }

        previewBridge.setCurrentSearchMatch(index)
    }

    private func lineNumber(for location: Int, in text: NSString) -> Int {
        guard location > 0 else { return 1 }
        let prefix = text.substring(with: NSRange(location: 0, length: min(location, text.length)))
        return prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
    }
}
