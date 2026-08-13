import SwiftUI

/// A quiet icon button for the assistant's header bar.
///
/// Kept borderless until pointed at: a row of permanently-outlined circles
/// reads as heavier than the title beside it, and each one costs width the
/// header does not have to spare.
struct AssistantHeaderButton: View {
    let symbol: String
    let help: String
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isEnabled ? MarkViewDesign.textSecondary : MarkViewDesign.textSecondary.opacity(0.4))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered && isEnabled ? Color.primary.opacity(0.09) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .accessibilityLabel(help)
        .help(help)
    }
}

/// The list of past conversations, and what they are costing in disk space.
///
/// Both halves matter. A history you cannot clear out is a folder that only
/// ever grows — and attachments are by far the heaviest thing here, so the
/// panel says plainly how much space they take and offers to reclaim it.
struct ChatHistoryView: View {
    @ObservedObject var aiService: AIService
    let onOpen: (UUID) -> Void
    let onClose: () -> Void

    @State private var report = ChatSessionStore.StorageReport(
        chatCount: 0, attachmentBytes: 0, orphanedBytes: 0
    )
    @State private var confirmingDeleteAll = false
    @State private var lastReclaimed: String?

    private var summaries: [ChatSessionSummary] { aiService.sessions.summaries }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)

            if summaries.isEmpty {
                emptyState
            } else {
                list
            }

            Divider().opacity(0.6)
            storageFooter
        }
        .frame(width: 380, height: 460)
        .onAppear(perform: refreshReport)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Chats")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Button {
                aiService.startNewChat()
                onClose()
            } label: {
                Label("New Chat", systemImage: "square.and.pencil")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Start a fresh conversation")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("No saved chats yet")
                .font(.system(size: 12, weight: .medium))
            Text("Conversations are kept here once you ask something.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(summaries) { summary in
                    ChatHistoryRow(
                        summary: summary,
                        isCurrent: summary.id == aiService.currentSessionID,
                        onOpen: {
                            onOpen(summary.id)
                            onClose()
                        },
                        onDelete: {
                            aiService.deleteChat(summary.id)
                            refreshReport()
                        }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private var storageFooter: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text("Attachments use \(report.attachmentSizeDescription)")
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 6)
                if let lastReclaimed {
                    Text(lastReclaimed)
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
            }

            Text("Images and files you send are stored once each, however many chats use them. Deleting a chat also deletes anything only it was using.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                if report.orphanedBytes > 0 {
                    Button("Reclaim \(report.orphanedSizeDescription)") {
                        let freed = aiService.sessions.reclaimOrphanedAttachments()
                        announce(freed)
                    }
                    .controlSize(.small)
                    .help("Delete leftover attachment files that no chat refers to any more")
                }

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    confirmingDeleteAll = true
                } label: {
                    Text("Delete All Chats")
                }
                .controlSize(.small)
                .disabled(summaries.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .confirmationDialog(
            "Delete all \(summaries.count) chats?",
            isPresented: $confirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                let freed = aiService.deleteAllChats()
                announce(freed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every conversation and all \(report.attachmentSizeDescription) of stored images and files. It can't be undone.")
        }
    }

    private func announce(_ freed: Int) {
        refreshReport()
        guard freed > 0 else { return }
        lastReclaimed = "Freed \(ByteCountFormatter.string(fromByteCount: Int64(freed), countStyle: .file))"
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            lastReclaimed = nil
        }
    }

    private func refreshReport() {
        report = aiService.sessions.storageReport()
    }
}

private struct ChatHistoryRow: View {
    let summary: ChatSessionSummary
    let isCurrent: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var confirmingDelete = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 5) {
                        Text(summary.updatedAt, format: .relative(presentation: .named))
                        Text("·")
                        Text("\(summary.messageCount) messages")
                        if summary.attachmentCount > 0 {
                            Text("·")
                            Image(systemName: "paperclip")
                                .font(.system(size: 8))
                            Text(summary.attachmentSizeDescription)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if isCurrent {
                    Text("Open")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(MarkViewDesign.accent.opacity(0.18)))
                        .foregroundStyle(MarkViewDesign.accent)
                }

                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .help("Delete this chat and anything only it was using")
                .accessibilityLabel("Delete chat “\(summary.title)”")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .confirmationDialog(
            "Delete “\(summary.title)”?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(summary.attachmentCount > 0
                 ? "This also deletes \(summary.attachmentSizeDescription) of images and files, unless another chat is using them."
                 : "This can't be undone.")
        }
    }
}
