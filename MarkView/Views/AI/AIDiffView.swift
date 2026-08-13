import SwiftUI

struct AIDiffView: View {
    let summary: String
    let originalText: String
    let proposedText: String
    let onAccept: () -> Void
    let onReject: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWipingIn = false
    @State private var isCollapsing = false

    private var diffSummary: DiffSummary {
        DiffEngine.computeDiff(original: originalText, modified: proposedText)
    }

    private var numberedLines: [(line: DiffLine, number: String)] {
        var sourceLine = 1
        var proposedLine = 1
        var result: [(line: DiffLine, number: String)] = []

        for line in diffSummary.lines {
            switch line.type {
            case .same:
                result.append((line, "\(sourceLine)"))
                sourceLine += 1
                proposedLine += 1
            case .removed:
                result.append((line, "\(sourceLine)"))
                sourceLine += 1
            case .added:
                result.append((line, "\(proposedLine)"))
                proposedLine += 1
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Proposed changes", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                HStack(spacing: 9) {
                    Text("+\(diffSummary.additions)")
                        .foregroundStyle(.green)
                    Text("−\(diffSummary.deletions)")
                        .foregroundStyle(.red)
                }
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)

            Divider()

            if !isCollapsing {
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(numberedLines.enumerated()), id: \.offset) { index, item in
                            diffLine(item.line, number: item.number, index: index)
                        }
                    }
                    .frame(minWidth: 620, alignment: .leading)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 300)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.42))
            }

            Divider()

            HStack(spacing: 8) {
                Button("Discard") {
                    discardWithAnimation()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Apply Changes") {
                    onAccept()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.11), lineWidth: 0.8)
        )
        .onAppear {
            if reduceMotion {
                isWipingIn = true
            } else {
                withAnimation(.easeOut(duration: 0.28)) {
                    isWipingIn = true
                }
            }
        }
    }

    private func diffLine(_ line: DiffLine, number: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(number)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 42, alignment: .trailing)
                .padding(.trailing, 10)

            Text(prefix(for: line.type))
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(prefixColor(for: line.type))
                .frame(width: 17)

            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 9)
        .background(backgroundColor(for: line.type))
        .opacity(line.type == .added && !isWipingIn && !reduceMotion ? 0 : 1)
        .offset(x: line.type == .added && !isWipingIn && !reduceMotion ? -14 : 0)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.28).delay(min(Double(index) * 0.02, 0.18)),
            value: isWipingIn
        )
    }

    private func prefix(for type: DiffType) -> String {
        switch type {
        case .added: return "+"
        case .removed: return "−"
        case .same: return " "
        }
    }

    private func prefixColor(for type: DiffType) -> Color {
        switch type {
        case .added: return .green
        case .removed: return .red
        case .same: return .secondary
        }
    }

    private func backgroundColor(for type: DiffType) -> Color {
        switch type {
        case .added: return Color.green.opacity(0.10)
        case .removed: return Color.red.opacity(0.085)
        case .same: return .clear
        }
    }

    private func discardWithAnimation() {
        guard !reduceMotion else {
            onReject()
            return
        }

        withAnimation(.easeOut(duration: 0.24)) {
            isCollapsing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            onReject()
        }
    }
}
