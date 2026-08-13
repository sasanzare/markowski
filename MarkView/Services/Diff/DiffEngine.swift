import Foundation

enum DiffType: Equatable {
    case added
    case removed
    case same
}

struct DiffLine: Identifiable, Equatable {
    let id = UUID()
    let type: DiffType
    let text: String
}

struct DiffSummary {
    let additions: Int
    let deletions: Int
    let lines: [DiffLine]
}

struct DiffEngine {
    /// Above this the LCS matrix costs more than the diff is worth. A 1,000 ×
    /// 1,000 alignment is already 8 MB and several hundred milliseconds.
    private static let maximumMatrixCells = 1_000_000

    static func computeDiff(original: String, modified: String) -> DiffSummary {
        let origLines = original.components(separatedBy: "\n")
        let modLines = modified.components(separatedBy: "\n")

        // Nearly every proposal rewrites a small region of a large document.
        // Peeling the identical head and tail first keeps the O(n·m) matrix
        // scoped to the part that actually differs — without it a 2,000-line
        // document allocates a 4,000,000-cell matrix, and the sidebar rebuilds
        // this diff on every SwiftUI body evaluation.
        var prefix = 0
        while prefix < origLines.count,
              prefix < modLines.count,
              origLines[prefix] == modLines[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < origLines.count - prefix,
              suffix < modLines.count - prefix,
              origLines[origLines.count - 1 - suffix] == modLines[modLines.count - 1 - suffix] {
            suffix += 1
        }

        let origMiddle = Array(origLines[prefix..<(origLines.count - suffix)])
        let modMiddle = Array(modLines[prefix..<(modLines.count - suffix)])

        var result: [DiffLine] = origLines[0..<prefix].map { DiffLine(type: .same, text: $0) }
        result += alignedDiff(origMiddle, modMiddle)
        result += origLines[(origLines.count - suffix)...].map { DiffLine(type: .same, text: $0) }

        let additions = result.filter { $0.type == .added }.count
        let deletions = result.filter { $0.type == .removed }.count

        return DiffSummary(additions: additions, deletions: deletions, lines: result)
    }

    /// Longest Common Subsequence (LCS) line diff of the differing region.
    private static func alignedDiff(_ origLines: [String], _ modLines: [String]) -> [DiffLine] {
        if origLines.isEmpty { return modLines.map { DiffLine(type: .added, text: $0) } }
        if modLines.isEmpty { return origLines.map { DiffLine(type: .removed, text: $0) } }

        guard origLines.count * modLines.count <= maximumMatrixCells else {
            // Too large to align line by line; report it as a wholesale
            // replacement rather than freezing the UI.
            return origLines.map { DiffLine(type: .removed, text: $0) }
                + modLines.map { DiffLine(type: .added, text: $0) }
        }

        let matrix = lcsMatrix(origLines, modLines)

        var i = origLines.count
        var j = modLines.count
        var tempLines: [DiffLine] = []

        while i > 0 || j > 0 {
            if i > 0 && j > 0 && origLines[i - 1] == modLines[j - 1] {
                tempLines.append(DiffLine(type: .same, text: origLines[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0 && (i == 0 || matrix[i][j - 1] >= matrix[i - 1][j]) {
                tempLines.append(DiffLine(type: .added, text: modLines[j - 1]))
                j -= 1
            } else if i > 0 && (j == 0 || matrix[i][j - 1] < matrix[i - 1][j]) {
                tempLines.append(DiffLine(type: .removed, text: origLines[i - 1]))
                i -= 1
            }
        }

        return tempLines.reversed()
    }

    static func firstChangedLine(original: String, modified: String) -> Int {
        let summary = computeDiff(original: original, modified: modified)
        var originalLine = 1

        for line in summary.lines {
            switch line.type {
            case .same:
                originalLine += 1
            case .removed:
                return originalLine
            case .added:
                return originalLine
            }
        }

        return max(1, originalLine)
    }

    private static func lcsMatrix(_ a: [String], _ b: [String]) -> [[Int]] {
        let m = a.count
        let n = b.count
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0..<m {
            for j in 0..<n {
                if a[i] == b[j] {
                    matrix[i + 1][j + 1] = matrix[i][j] + 1
                } else {
                    matrix[i + 1][j + 1] = max(matrix[i + 1][j], matrix[i][j + 1])
                }
            }
        }
        return matrix
    }
}
