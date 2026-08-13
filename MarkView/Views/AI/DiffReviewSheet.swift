import SwiftUI

struct DiffReviewSheet: View {
    let summary: String
    let originalText: String
    let proposedText: String
    let onApply: () -> Void
    let onDiscard: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var diffSummary: DiffSummary {
        DiffEngine.computeDiff(original: originalText, modified: proposedText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Proposed Changes")
                        .font(.headline)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 12) {
                    Text("+\(diffSummary.additions)")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                    Text("-\(diffSummary.deletions)")
                        .font(.caption.bold())
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Diff Scroll Area
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diffSummary.lines) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Text(linePrefix(for: line.type))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(lineColor(for: line.type))
                                .frame(width: 16)

                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(lineColor(for: line.type))

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 12)
                        .background(backgroundColor(for: line.type))
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Footer Actions
            HStack {
                Button("Discard Changes", role: .destructive) {
                    onDiscard()
                    dismiss()
                }

                Spacer()

                Button("Apply Changes") {
                    onApply()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 650, minHeight: 450)
    }

    private func linePrefix(for type: DiffType) -> String {
        switch type {
        case .added: return "+"
        case .removed: return "-"
        case .same: return " "
        }
    }

    private func lineColor(for type: DiffType) -> StringColor {
        switch type {
        case .added: return .green
        case .removed: return .red
        case .same: return .primary
        }
    }

    private func backgroundColor(for type: DiffType) -> Color {
        switch type {
        case .added: return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.12)
        case .same: return Color.clear
        }
    }
}

typealias StringColor = Color
