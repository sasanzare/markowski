import Foundation

/// Cleanups that Persian Markdown needs and a plain text editor never does.
///
/// Text typed on an Arabic keyboard, pasted from the web, or produced by OCR
/// routinely mixes Arabic letters into Persian words, uses Latin digits and
/// punctuation, and puts a plain space where a zero-width non-joiner belongs
/// (`می شود` instead of `می‌شود`). None of that is visible as an error, but all
/// of it makes text search, sorting, and rendering behave badly.
enum PersianTextTools {

    /// U+200C ZERO WIDTH NON-JOINER — the "نیم‌فاصله".
    static let zwnj = "\u{200C}"
    /// U+200F RIGHT-TO-LEFT MARK, for pinning direction around neutral runs.
    static let rlm = "\u{200F}"
    /// U+200E LEFT-TO-RIGHT MARK.
    static let lrm = "\u{200E}"

    /// Arabic forms that should be their Persian equivalents.
    ///
    /// Keyed by scalar, and applied per scalar, because a zero-width
    /// non-joiner binds to the letter beside it: `مي‌` is one grapheme cluster,
    /// and `replacingOccurrences(of: "ي")` does not find a letter inside one.
    /// Replacing by substring therefore fixed `كتاب` but silently left
    /// `مي‌شود` alone — that is, it failed on precisely the words that already
    /// use a نیم‌فاصله, which is most real Persian prose.
    private static let letterReplacements: [UnicodeScalar: UnicodeScalar] = [
        "ي": "ی",   // Arabic yeh → Farsi yeh
        "ى": "ی",   // Alef maksura → Farsi yeh
        "ﻯ": "ی",
        "ك": "ک",   // Arabic kaf → Keheh
        "ﻙ": "ک",
        "ة": "ه",   // Teh marbuta → heh
        "ۀ": "ه",
        "أ": "ا",
        "إ": "ا",
        "ٱ": "ا",
        "ؤ": "و",
        "ئ": "ی",
        // Arabic-Indic digits are always wrong in Persian text.
        "٠": "۰", "١": "۱", "٢": "۲", "٣": "۳", "٤": "۴",
        "٥": "۵", "٦": "۶", "٧": "۷", "٨": "۸", "٩": "۹"
    ]

    private static let arabicIndicDigits = Array("٠١٢٣٤٥٦٧٨٩")
    private static let persianDigits = Array("۰۱۲۳۴۵۶۷۸۹")
    private static let latinDigits = Array("0123456789")

    private static let punctuationReplacements: [(String, String)] = [
        ("?", "؟"),
        (";", "؛"),
        (",", "،")
    ]

    // MARK: - Individual operations

    /// Arabic letter forms → their Persian equivalents.
    static func normalizeLetters(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            scalars.append(letterReplacements[scalar] ?? scalar)
        }
        return String(scalars)
    }

    static func toPersianDigits(_ text: String) -> String {
        mapDigits(text, from: latinDigits, to: persianDigits)
    }

    static func toLatinDigits(_ text: String) -> String {
        mapDigits(mapDigits(text, from: persianDigits, to: latinDigits), from: arabicIndicDigits, to: latinDigits)
    }

    /// Latin punctuation → Persian punctuation, and tidies the spacing around
    /// it (Persian puts no space before a comma, one after).
    ///
    /// Only punctuation that actually belongs to Persian text is converted.
    /// Replacing every `,` and `?` in the document turned "Hello, world" into
    /// "Hello، world" — so in any document that mixes the two languages, the
    /// cleanup damaged the English half.
    static func normalizePunctuation(_ text: String) -> String {
        let characters = Array(text)
        var converted = ""
        converted.reserveCapacity(characters.count)

        for (index, character) in characters.enumerated() {
            guard let persian = punctuationReplacements.first(where: { $0.0 == String(character) })?.1 else {
                converted.append(character)
                continue
            }
            let neighbours = [
                nearestVisible(characters, from: index, step: -1),
                nearestVisible(characters, from: index, step: 1)
            ]
            converted.append(neighbours.contains(where: { $0.map(isPersianLetter) == true })
                ? persian
                : String(character))
        }

        // These marks exist only in Persian, so spacing around them is safe to
        // normalise wherever they appear.
        var result = converted.replacingOccurrences(
            of: "[ \\t]+([،؛؟])",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "([،؛؟])(?=[^\\s])",
            with: "$1 ",
            options: .regularExpression
        )
        return result
    }

    private static func nearestVisible(
        _ characters: [Character],
        from index: Int,
        step: Int
    ) -> Character? {
        var cursor = index + step
        while cursor >= 0, cursor < characters.count {
            let candidate = characters[cursor]
            if !candidate.isWhitespace { return candidate }
            cursor += step
        }
        return nil
    }

    static func isPersianLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    }

    /// Inserts the zero-width non-joiner where Persian morphology wants it:
    /// after the prefixes `می`/`نمی`, and before the common suffixes.
    static func applyZeroWidthNonJoiner(_ text: String) -> String {
        var result = text

        // "می رود" / "نمی رود" → "می‌رود" / "نمی‌رود"
        result = result.replacingOccurrences(
            of: "(^|[\\s\(zwnj)])(ن?می) +(?=[\\u0621-\\u06CC])",
            with: "$1$2\(zwnj)",
            options: .regularExpression
        )

        // " ها" / " های" / " تر" / " ترین" / " ام" … attach to the word before.
        let suffixes = ["ها", "هایی", "های", "هایم", "تری", "ترین", "تر", "ام", "ات", "اش", "اید", "اند"]
        for suffix in suffixes {
            result = result.replacingOccurrences(
                of: "([\\u0621-\\u06CC]) +(\(suffix))(?![\\u0621-\\u06CC])",
                with: "$1\(zwnj)$2",
                options: .regularExpression
            )
        }

        return result
    }

    /// Collapses runs of spaces and strips trailing whitespace per line, which
    /// pasted Persian text is usually full of. Markdown's two-space hard break
    /// is preserved.
    static func tidyWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: "\n")
            .map { line -> String in
                let hasHardBreak = line.hasSuffix("  ") && !line.trimmingCharacters(in: .whitespaces).isEmpty
                var tidied = line.replacingOccurrences(
                    of: "[ \\t]{2,}",
                    with: " ",
                    options: .regularExpression
                )
                tidied = tidied.replacingOccurrences(
                    of: "[ \\t]+$",
                    with: "",
                    options: .regularExpression
                )
                return hasHardBreak ? tidied + "  " : tidied
            }
            .joined(separator: "\n")
    }

    /// Everything at once — the "Clean up Persian text" action.
    static func fixAll(_ text: String) -> String {
        let prose = outsideCode(text) { segment in
            var result = normalizeLetters(segment)
            result = normalizePunctuation(result)
            result = applyZeroWidthNonJoiner(result)
            return result
        }
        // Whitespace tidying is line-based, so it runs over the whole string
        // rather than per segment — but it still has to leave code indentation
        // alone, which `outsideCode` handles for the fenced parts.
        return outsideCode(prose, tidyWhitespace)
    }

    // MARK: - Leaving code alone

    /// Applies a rewrite to everything except code.
    ///
    /// These transforms are about prose. Run over a whole Markdown document
    /// they also rewrote fenced blocks and inline spans, turning `arr[1,2]`
    /// into `arr[1،2]` and `1` into `۱` — silently breaking code the user never
    /// meant to touch.
    static func outsideCode(_ text: String, _ transform: (String) -> String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var index = text.startIndex
        var prose = ""

        func flushProse() {
            guard !prose.isEmpty else { return }
            result += transform(prose)
            prose = ""
        }

        while index < text.endIndex {
            if let fence = fenceRange(in: text, at: index) {
                flushProse()
                result += text[fence]
                index = fence.upperBound
                continue
            }
            if let span = inlineCodeRange(in: text, at: index) {
                flushProse()
                result += text[span]
                index = span.upperBound
                continue
            }
            prose.append(text[index])
            index = text.index(after: index)
        }
        flushProse()
        return result
    }

    /// A fenced block starting at `index`, if one does.
    private static func fenceRange(in text: String, at index: String.Index) -> Range<String.Index>? {
        // Only at the start of a line.
        let atLineStart = index == text.startIndex || text[text.index(before: index)] == "\n"
        guard atLineStart else { return nil }

        let opening = text[index...].prefix { $0 == "`" || $0 == "~" }
        guard opening.count >= 3, let marker = opening.first else { return nil }

        let fence = String(repeating: String(marker), count: opening.count)
        var cursor = index
        // Past the opening line.
        while cursor < text.endIndex, text[cursor] != "\n" { cursor = text.index(after: cursor) }

        while cursor < text.endIndex {
            let lineStart = text.index(after: cursor)
            guard lineStart <= text.endIndex else { break }
            var lineEnd = lineStart
            while lineEnd < text.endIndex, text[lineEnd] != "\n" { lineEnd = text.index(after: lineEnd) }

            if text[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                return index..<lineEnd
            }
            if lineEnd == text.endIndex { break }
            cursor = lineEnd
        }
        // Unterminated: treat the rest of the document as code, which is what
        // the parser does too.
        return index..<text.endIndex
    }

    /// A `` `code span` `` starting at `index`, if one does.
    private static func inlineCodeRange(in text: String, at index: String.Index) -> Range<String.Index>? {
        guard text[index] == "`" else { return nil }
        let ticks = text[index...].prefix { $0 == "`" }.count
        let closing = String(repeating: "`", count: ticks)

        var cursor = text.index(index, offsetBy: ticks, limitedBy: text.endIndex) ?? text.endIndex
        while cursor < text.endIndex {
            if text[cursor] == "`" {
                let run = text[cursor...].prefix { $0 == "`" }.count
                if run == ticks {
                    let end = text.index(cursor, offsetBy: run, limitedBy: text.endIndex) ?? text.endIndex
                    return index..<end
                }
                cursor = text.index(cursor, offsetBy: run, limitedBy: text.endIndex) ?? text.endIndex
                continue
            }
            // A code span does not span a blank line.
            if text[cursor] == "\n" { return nil }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    // MARK: - Direction marks

    /// Wraps a neutral run (digits, punctuation, a Latin word) in RTL marks so
    /// it stops jumping to the wrong side of a Persian line.
    static func pinDirection(_ text: String, rightToLeft: Bool) -> String {
        let mark = rightToLeft ? rlm : lrm
        let stripped = removeDirectionMarks(text)
        return mark + stripped + mark
    }

    static func removeDirectionMarks(_ text: String) -> String {
        text
            .replacingOccurrences(of: rlm, with: "")
            .replacingOccurrences(of: lrm, with: "")
    }

    // MARK: - Detection

    /// Whether this text is Persian/Arabic enough to be worth offering the
    /// Persian tools for. Used to surface them rather than to gate them.
    static func containsPersian(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x0600...0x06FF).contains(scalar.value)
                || (0xFB50...0xFDFF).contains(scalar.value)
                || (0xFE70...0xFEFF).contains(scalar.value)
        }
    }

    /// Per scalar, for the same reason the letter map is.
    private static func mapDigits(_ text: String, from: [Character], to: [Character]) -> String {
        let source = from.compactMap { $0.unicodeScalars.first }
        let target = to.compactMap { $0.unicodeScalars.first }
        guard source.count == target.count else { return text }

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            if let index = source.firstIndex(of: scalar) {
                scalars.append(target[index])
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// Counts Latin and Persian digits outside code, for the digit control.
    static func digitCounts(in text: String) -> (latin: Int, persian: Int) {
        var latin = 0
        var persian = 0
        _ = outsideCode(text) { segment in
            for character in segment {
                if latinDigits.contains(character) { latin += 1 }
                if persianDigits.contains(character) || arabicIndicDigits.contains(character) { persian += 1 }
            }
            return segment
        }
        return (latin, persian)
    }
}

/// One thing wrong with a piece of Persian text.
///
/// Carrying the count and a worked example is the whole point: these problems
/// are invisible on screen — a نیم‌فاصله is a zero-width character, an Arabic
/// ی looks identical to a Persian one — so a button that silently rewrites the
/// document asks for trust it has no way to earn. "47 Arabic letters · مي‌شود →
/// می‌شود" earns it.
struct PersianIssue: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case arabicLetters
        case missingZWNJ
        case latinPunctuation
        case punctuationSpacing
        case extraSpaces

        var title: String {
            switch self {
            case .arabicLetters: return "Arabic letters"
            case .missingZWNJ: return "Missing نیم‌فاصله"
            case .latinPunctuation: return "Latin punctuation"
            case .punctuationSpacing: return "Spacing around punctuation"
            case .extraSpaces: return "Double spaces"
            }
        }

        /// Plain language, because "normalise letters" explains nothing to
        /// someone who just wants their text to be right.
        var explanation: String {
            switch self {
            case .arabicLetters:
                return "Arabic ي and ك look identical to Persian ی and ک but break search and sorting."
            case .missingZWNJ:
                return "می and suffixes like ها should join with a half-space, not a full one."
            case .latinPunctuation:
                return "Persian uses ، ؛ ؟ rather than , ; ?"
            case .punctuationSpacing:
                return "Persian puts no space before a comma and one after it."
            case .extraSpaces:
                return "Runs of spaces left over from pasting."
            }
        }

        var symbolName: String {
            switch self {
            case .arabicLetters: return "character"
            case .missingZWNJ: return "arrow.right.and.line.vertical.and.arrow.left"
            case .latinPunctuation: return "quote.closing"
            case .punctuationSpacing: return "space"
            case .extraSpaces: return "arrow.left.and.right"
            }
        }

        /// The command that fixes this one issue on its own.
        var command: FormatCommand {
            switch self {
            case .arabicLetters: return .persianNormalizeLetters
            case .missingZWNJ: return .persianZWNJ
            case .latinPunctuation, .punctuationSpacing: return .persianPunctuation
            case .extraSpaces: return .persianTidyWhitespace
            }
        }
    }

    var id: String { kind.rawValue }
    let kind: Kind
    let count: Int
    /// A real occurrence from the text, and what it becomes.
    let example: (before: String, after: String)?

    static func == (lhs: PersianIssue, rhs: PersianIssue) -> Bool {
        lhs.kind == rhs.kind && lhs.count == rhs.count
            && lhs.example?.before == rhs.example?.before
            && lhs.example?.after == rhs.example?.after
    }
}

/// Finds what is actually wrong with a piece of Persian text.
enum PersianTextAnalyzer {

    /// Every problem present in `text`, ignoring code.
    static func analyze(_ text: String) -> [PersianIssue] {
        // Only prose is examined, for the same reason only prose is rewritten.
        var prose = ""
        _ = PersianTextTools.outsideCode(text) { segment in
            prose += segment
            return segment
        }
        guard PersianTextTools.containsPersian(prose) else { return [] }

        return PersianIssue.Kind.allCases.compactMap { kind in
            let found = occurrences(of: kind, in: prose)
            guard found.count > 0 else { return nil }
            return PersianIssue(kind: kind, count: found.count, example: found.example)
        }
    }

    /// Whether running every fix would change anything at all.
    static func isClean(_ text: String) -> Bool {
        analyze(text).isEmpty
    }

    private static func occurrences(
        of kind: PersianIssue.Kind,
        in text: String
    ) -> (count: Int, example: (before: String, after: String)?) {
        switch kind {
        case .arabicLetters:
            let count = text.unicodeScalars.filter { arabicOffenders.contains($0) }.count
            return (count, exampleWord(in: text, fix: PersianTextTools.normalizeLetters))

        case .missingZWNJ:
            let fixed = PersianTextTools.applyZeroWidthNonJoiner(text)
            let count = max(0, zwnjCount(fixed) - zwnjCount(text))
            return (count, exampleLine(in: text, fix: PersianTextTools.applyZeroWidthNonJoiner))

        case .latinPunctuation:
            let count = countConvertedPunctuation(in: text)
            return (count, exampleLine(in: text, fix: PersianTextTools.normalizePunctuation))

        case .punctuationSpacing:
            let pattern = "[ \\t]+[،؛؟]|[،؛؟](?=[^\\s])"
            let count = matchCount(pattern, in: text)
            return (count, exampleLine(in: text, fix: PersianTextTools.normalizePunctuation))

        case .extraSpaces:
            // A Markdown hard break is a deliberate pair of trailing spaces.
            let count = matchCount("\\S[ \\t]{2,}\\S", in: text)
            return (count, exampleLine(in: text, fix: PersianTextTools.tidyWhitespace))
        }
    }

    /// How many Latin marks the converter would actually touch — which is not
    /// all of them, since English punctuation is left alone.
    private static func countConvertedPunctuation(in text: String) -> Int {
        let original = Array(text)
        let converted = Array(PersianTextTools.normalizePunctuation(text))
        guard original.count == converted.count else {
            // Spacing changed the length; fall back to counting the marks that
            // differ by scanning the shorter of the two.
            return zip(original, converted).filter { $0 != $1 }.count
        }
        return zip(original, converted).filter { $0 != $1 }.count
    }

    /// Arabic forms that have a Persian equivalent, as scalars.
    ///
    /// Scalars, not `Character`s: a زero-width non-joiner binds to the letter
    /// beside it, so `مي‌` is a *single* grapheme cluster and comparing whole
    /// characters against "ي" never matches — in exactly the text most likely
    /// to contain these letters.
    private static let arabicOffenders: Set<UnicodeScalar> = [
        "ي", "ى", "ك", "ة", "ۀ", "أ", "إ", "ٱ", "ؤ", "ئ",
        "٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"
    ]

    /// Counts half-spaces by scalar, for the same reason: searching a string
    /// for the ZWNJ substring does not find the ones bound into a cluster.
    private static func zwnjCount(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.value == 0x200C }.count
    }

    private static func matchCount(_ pattern: String, in text: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return expression.numberOfMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length)
        )
    }

    /// The first word holding an Arabic form, and what it becomes.
    private static func exampleWord(
        in text: String,
        fix: (String) -> String
    ) -> (before: String, after: String)? {
        for word in text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            guard word.unicodeScalars.contains(where: { arabicOffenders.contains($0) }) else { continue }
            let before = String(word.prefix(24))
            let after = fix(before)
            return before == after ? nil : (before, after)
        }
        return nil
    }

    /// The first short run of text the fix actually changes.
    private static func exampleLine(in text: String, fix: (String) -> String) -> (before: String, after: String)? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, fix(trimmed) != trimmed else { continue }

            // Narrow to the shortest window that still shows the change, so the
            // example fits in a sidebar.
            let words = trimmed.split(separator: " ", omittingEmptySubsequences: false)
            for size in 2...max(2, min(5, words.count)) {
                for start in 0...(max(0, words.count - size)) {
                    let window = words[start..<min(start + size, words.count)].joined(separator: " ")
                    let fixed = fix(window)
                    if fixed != window, window.count <= 34 {
                        return (window, fixed)
                    }
                }
            }
            let before = String(trimmed.prefix(34))
            return (before, fix(before))
        }
        return nil
    }
}
