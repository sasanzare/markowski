import Foundation

struct DocumentLocation: Codable, Equatable, Hashable {
    let heading: String?
    let quote: String?
    let startLine: Int?
    let endLine: Int?
    let blockId: String?

    var displayTitle: String {
        if let h = heading, !h.isEmpty {
            return h
        }
        if let start = startLine, let end = endLine {
            return "Lines \(start)–\(end)"
        }
        if let q = quote, !q.isEmpty {
            let prefix = q.prefix(30)
            return "“\(prefix)...”"
        }
        return "Referenced Section"
    }
}
