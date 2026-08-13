import Foundation

struct DocumentBlock: Identifiable, Equatable {
    let id: String // e.g. block-1, block-2
    let lineRange: ClosedRange<Int>
    let headingTitle: String?
    let contentText: String
}

final class DocumentIndex {
    private(set) var blocks: [DocumentBlock] = []
    private(set) var headings: [String] = []

    func buildIndex(from text: String) {
        blocks.removeAll()
        headings.removeAll()

        let lines = text.components(separatedBy: "\n")
        var currentBlockText = ""
        var currentStartLine = 1
        var blockCounter = 1
        var currentHeading: String? = nil

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                // Save previous block if exists
                if !currentBlockText.isEmpty {
                    let block = DocumentBlock(
                        id: "block-\(blockCounter)",
                        lineRange: currentStartLine...(lineNumber - 1),
                        headingTitle: currentHeading,
                        contentText: currentBlockText
                    )
                    blocks.append(block)
                    blockCounter += 1
                    currentBlockText = ""
                }

                let headingText = trimmed.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                currentHeading = headingText
                headings.append(headingText)
                currentStartLine = lineNumber
                currentBlockText = line
            } else if trimmed.isEmpty {
                if !currentBlockText.isEmpty {
                    let block = DocumentBlock(
                        id: "block-\(blockCounter)",
                        lineRange: currentStartLine...lineNumber,
                        headingTitle: currentHeading,
                        contentText: currentBlockText
                    )
                    blocks.append(block)
                    blockCounter += 1
                    currentBlockText = ""
                }
                currentStartLine = lineNumber + 1
            } else {
                if currentBlockText.isEmpty {
                    currentStartLine = lineNumber
                }
                currentBlockText += (currentBlockText.isEmpty ? "" : "\n") + line
            }
        }

        if !currentBlockText.isEmpty {
            let block = DocumentBlock(
                id: "block-\(blockCounter)",
                lineRange: currentStartLine...lines.count,
                headingTitle: currentHeading,
                contentText: currentBlockText
            )
            blocks.append(block)
        }
    }

    func resolveLocation(_ location: DocumentLocation) -> DocumentBlock? {
        // 1. Resolve deterministic renderer IDs first.
        if let blockID = location.blockId,
           let match = blocks.first(where: { $0.id == blockID }) {
            return match
        }

        // 2. Resolve by heading if present
        if let h = location.heading, !h.isEmpty {
            if let match = blocks.first(where: { $0.headingTitle?.localizedCaseInsensitiveContains(h) == true }) {
                return match
            }
        }

        // 3. Resolve by quote if present. A model's quote is often *close* to
        // the source rather than identical — re-wrapped, or with the Markdown
        // syntax dropped — so retry on looser forms before giving up.
        if let q = location.quote, !q.isEmpty {
            for candidate in Self.quoteCandidates(for: q) {
                if let match = blocks.first(where: { $0.contentText.localizedCaseInsensitiveContains(candidate) }) {
                    return match
                }

                // A model quotes what it *read*, so "Run npm install first"
                // has to match a source line of "Run **npm install** first".
                let normalizedCandidate = Self.normalizedForMatching(candidate)
                guard normalizedCandidate.count >= 3 else { continue }
                if let match = blocks.first(where: {
                    Self.normalizedForMatching($0.contentText).contains(normalizedCandidate)
                }) {
                    return match
                }
            }
        }

        // 4. Resolve by line range
        if let start = location.startLine {
            if let match = blocks.first(where: { $0.lineRange.contains(start) }) {
                return match
            }
        }

        return nil
    }

    /// Drops Markdown emphasis and collapses whitespace so a quote can be
    /// compared against the source it was read from.
    static func normalizedForMatching(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[*_`~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Strips the Markdown a quote still carries, leaving the words that are
    /// actually on screen.
    ///
    /// The assistant quotes the *source*, so it hands back things like
    /// `- [x] Ship the beta`. Neither the editor canvas nor the rendered
    /// preview contains `- [x] ` — the marker became a bullet and a checkbox —
    /// so searching for the quote verbatim finds nothing and the citation
    /// appears to do nothing when clicked.
    static func plainText(fromMarkdown markdown: String) -> String {
        var text = markdown.trimmingCharacters(in: .whitespaces)
        for pattern in [
            "^\\s*>+\\s*",           // block quote
            "^\\s*#{1,6}\\s+",       // heading
            "^\\s*[-*+]\\s+",        // bullet
            "^\\s*\\d+[.)]\\s+",     // ordered item
            "^\\s*\\[[ xX]\\]\\s*"   // task checkbox
        ] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return text
            // Links and images render as their label alone.
            .replacingOccurrences(
                of: "!?\\[([^\\]]*)\\]\\([^)]*\\)",
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(of: "[*_`~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    static func quoteCandidates(for quote: String) -> [String] {
        let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates = [trimmed]

        let firstLine = trimmed.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? trimmed
        if firstLine != trimmed {
            candidates.append(firstLine)
        }

        // The stripped forms are what the canvas and the preview actually hold.
        for source in [firstLine, trimmed] {
            let plain = plainText(fromMarkdown: source)
            if !plain.isEmpty, !candidates.contains(plain) {
                candidates.append(plain)
            }
        }

        // A long quote only has to agree with the source on its opening.
        if let longest = candidates.max(by: { $0.count < $1.count }), longest.count > 40 {
            let opening = String(plainText(fromMarkdown: longest).prefix(40))
                .trimmingCharacters(in: .whitespaces)
            if !opening.isEmpty, !candidates.contains(opening) {
                candidates.append(opening)
            }
        }

        return candidates.filter { $0.count >= 3 }
    }
}
