import Foundation

/// Maps text the user selected in the *rendered* preview back to a range in the
/// Markdown source.
///
/// The preview shows `Date: 2026`, the source says `**Date:** 2026`. A plain
/// `range(of:)` finds nothing, which is why formatting commands appeared to do
/// nothing at all in Preview mode: the range fell back to the start of the
/// document and the command was applied somewhere the user wasn't looking.
///
/// So matching is done on a normalised projection of the source — Markdown
/// punctuation removed, whitespace collapsed — while keeping an index map back
/// to real source offsets.
enum SourceSelectionResolver {

    /// Characters that exist in the source purely as Markdown syntax and never
    /// appear in the rendered text.
    private static let syntaxCharacters: Set<Character> = ["*", "_", "`", "~", "#", ">"]

    static func range(of selection: String, in source: String) -> NSRange? {
        let needle = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }

        let nsSource = source as NSString

        // The common case: the selection is literally in the source.
        let exact = nsSource.range(of: needle)
        if exact.location != NSNotFound {
            return exact
        }

        // Otherwise match on the normalised projection.
        let projection = normalize(source)
        let normalizedNeedle = normalizeNeedle(needle)
        guard !normalizedNeedle.isEmpty else { return nil }

        guard let found = projection.text.range(of: normalizedNeedle) else { return nil }

        let startIndex = projection.text.distance(from: projection.text.startIndex, to: found.lowerBound)
        let endIndex = projection.text.distance(from: projection.text.startIndex, to: found.upperBound)
        guard startIndex < projection.offsets.count, endIndex > 0, endIndex <= projection.offsets.count else {
            return nil
        }

        let sourceStart = projection.offsets[startIndex]
        // `offsets` maps each normalised character to where it starts in the
        // source, so the end is one past the last matched character.
        let lastCharacterStart = projection.offsets[endIndex - 1]
        let sourceEnd = lastCharacterStart + projection.lengths[endIndex - 1]

        guard sourceEnd > sourceStart, sourceEnd <= nsSource.length else { return nil }
        return NSRange(location: sourceStart, length: sourceEnd - sourceStart)
    }

    private struct Projection {
        var text: String = ""
        /// Source offset of each character in `text`.
        var offsets: [Int] = []
        /// UTF-16 length in the source of each character in `text`.
        var lengths: [Int] = []
    }

    private static func normalize(_ source: String) -> Projection {
        var projection = Projection()
        var offset = 0
        var pendingWhitespace = false
        var atLineStart = true

        for character in source {
            let utf16Length = String(character).utf16.count
            defer { offset += utf16Length }

            if character == "\n" {
                pendingWhitespace = !projection.text.isEmpty
                atLineStart = true
                continue
            }

            if character == " " || character == "\t" {
                // Leading indentation is layout, not content.
                if !atLineStart {
                    pendingWhitespace = !projection.text.isEmpty
                }
                continue
            }

            // Line-leading list and quote markers are rendered as bullets and
            // borders, not as text.
            if atLineStart, character == "-" || character == "+" || character == "*" || character == ">" {
                continue
            }

            if syntaxCharacters.contains(character) {
                continue
            }

            if pendingWhitespace {
                projection.text.append(" ")
                projection.offsets.append(offset)
                projection.lengths.append(0)
                pendingWhitespace = false
            }

            projection.text.append(character)
            projection.offsets.append(offset)
            projection.lengths.append(utf16Length)
            atLineStart = false
        }

        return projection
    }

    private static func normalizeNeedle(_ needle: String) -> String {
        var result = ""
        var pendingWhitespace = false

        for character in needle {
            if character.isWhitespace {
                pendingWhitespace = !result.isEmpty
                continue
            }
            if syntaxCharacters.contains(character) {
                continue
            }
            if pendingWhitespace {
                result.append(" ")
                pendingWhitespace = false
            }
            result.append(character)
        }
        return result
    }
}
