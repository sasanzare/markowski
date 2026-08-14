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

    /// Tries semantic candidates in order and stops at the first visible hit.
    /// This matters for rendered-only content such as Mermaid: the reference
    /// may quote `sequenceDiagram`, but that source token disappears when the
    /// diagram becomes SVG, while its surrounding heading remains visible.
    func findFirst(_ queries: [String]) {
        let unique = queries.reduce(into: [String]()) { result, query in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !result.contains(trimmed) else { return }
            result.append(trimmed)
        }
        guard !unique.isEmpty else { return }
        let attempts = unique.map { "findText(\(json($0)))" }.joined(separator: " || ")
        evaluate("\(attempts);")
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
            let candidates = [location.quote, location.heading, block?.contentText]
                .compactMap { $0 }
                .flatMap { DocumentIndex.quoteCandidates(for: $0) }
            if !candidates.isEmpty {
                previewBridge.findFirst(candidates)
            } else if let blockID = location.blockId {
                previewBridge.scrollToBlock(blockID, reduceMotion: reduceMotion)
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
    ///
    /// Returns whether anything was found, so a citation that leads nowhere can
    /// be reported rather than silently doing nothing.
    @discardableResult
    private func revealInCanvas(_ candidates: [String]) -> Bool {
        guard let textView = canvasTextView else { return false }
        let haystack = textView.string as NSString

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }

            if let range = locate(trimmed, in: haystack) {
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
                textView.showFindIndicator(for: range)
                return true
            }
        }

        // Nothing matched whole; try the opening words. A model routinely
        // reflows or trims the tail of what it quotes, rarely the start.
        for candidate in candidates {
            let words = candidate.split(separator: " ")
            guard words.count > 3 else { continue }
            let opening = words.prefix(min(6, words.count - 1)).joined(separator: " ")
            guard opening.count >= 6, let range = locate(opening, in: haystack) else { continue }

            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
            return true
        }
        return false
    }

    /// Finds `needle` in `haystack`, tolerating the whitespace differences
    /// between a quoted source line and the laid-out document.
    private func locate(_ needle: String, in haystack: NSString) -> NSRange? {
        let direct = haystack.range(of: needle, options: [.caseInsensitive])
        if direct.location != NSNotFound { return direct }

        // Collapse runs of whitespace on both sides, keeping a map back to the
        // original offsets so the caret still lands in the right place.
        var flattened = ""
        var offsets: [Int] = []
        var previousWasSpace = false

        for index in 0..<haystack.length {
            let character = Character(UnicodeScalar(haystack.character(at: index)) ?? " ")
            if character.isWhitespace || character.isNewline {
                if previousWasSpace || flattened.isEmpty { continue }
                flattened.append(" ")
                offsets.append(index)
                previousWasSpace = true
            } else {
                flattened.append(character)
                offsets.append(index)
                previousWasSpace = false
            }
        }

        let flatNeedle = needle
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard flatNeedle.count >= 3,
              let found = flattened.range(of: flatNeedle, options: [.caseInsensitive]) else {
            return nil
        }

        let start = flattened.distance(from: flattened.startIndex, to: found.lowerBound)
        let end = flattened.distance(from: flattened.startIndex, to: found.upperBound)
        guard start < offsets.count, end > 0, end <= offsets.count else { return nil }

        let location = offsets[start]
        let upper = end < offsets.count ? offsets[end] : haystack.length
        guard upper > location else { return nil }
        return NSRange(location: location, length: upper - location)
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
