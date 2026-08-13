import AppKit
import CryptoKit
import Foundation

/// One conversation with the assistant.
struct ChatSession: Identifiable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messages: [AIMessage]

    init(
        id: UUID = UUID(),
        title: String = ChatSession.untitled,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [AIMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    static let untitled = "New chat"

    var isEmpty: Bool { messages.isEmpty }

    /// A name taken from the first thing the user actually asked, so the
    /// history reads as a list of questions rather than of timestamps.
    static func derivedTitle(from messages: [AIMessage]) -> String {
        guard let first = messages.first(where: { $0.sender == .user }) else { return untitled }

        let line = first.content
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else {
            return first.attachments.isEmpty ? untitled : "Chat about an image"
        }
        return String(line.prefix(60))
    }

    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        lhs.id == rhs.id && lhs.updatedAt == rhs.updatedAt && lhs.messages.count == rhs.messages.count
    }
}

/// What the history list shows, without touching a single attachment.
///
/// Kept separate from the session itself so opening the list costs one small
/// file read. Folding this into the sessions would mean decoding every stored
/// image just to draw a list of titles.
struct ChatSessionSummary: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var messageCount: Int
    var attachmentCount: Int
    /// Bytes this chat's attachments occupy, before de-duplication.
    var attachmentBytes: Int

    var attachmentSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: Int64(attachmentBytes), countStyle: .file)
    }
}

// MARK: - Attachments on disk

/// Attachment bytes, stored once per distinct file.
///
/// Blobs are named by the hash of their own contents, which buys three things
/// that matter for keeping this manageable: the same screenshot attached to
/// five chats occupies one file; a chat's JSON stays small enough to list
/// instantly; and "what is this actually costing me" has an answer, because
/// the bytes are in one place that can be measured and swept.
final class AttachmentStore {
    private let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Writes the bytes if they are not already here, and returns their hash.
    @discardableResult
    func store(_ data: Data) -> String {
        let digest = Self.hash(of: data)
        let url = directory.appendingPathComponent(digest)
        // Same contents, same name: an existing file is already correct.
        if !fileManager.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        return digest
    }

    func load(_ digest: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(digest))
    }

    func exists(_ digest: String) -> Bool {
        fileManager.fileExists(atPath: directory.appendingPathComponent(digest).path)
    }

    var allDigests: Set<String> {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { !$0.hasPrefix(".") })
    }

    var totalBytes: Int {
        allDigests.reduce(0) { total, digest in
            total + byteCount(of: digest)
        }
    }

    func byteCount(of digest: String) -> Int {
        let url = directory.appendingPathComponent(digest)
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// Deletes every blob no chat refers to any more, and reports what that
    /// freed.
    ///
    /// This is what makes deleting a chat mean something: without it the
    /// messages would go and the megabytes would stay, invisible, forever.
    @discardableResult
    func collectGarbage(keeping referenced: Set<String>) -> Int {
        var freed = 0
        for digest in allDigests where !referenced.contains(digest) {
            freed += byteCount(of: digest)
            try? fileManager.removeItem(at: directory.appendingPathComponent(digest))
        }
        return freed
    }

    /// Bytes held by blobs nothing refers to.
    func orphanedBytes(referenced: Set<String>) -> Int {
        allDigests
            .filter { !referenced.contains($0) }
            .reduce(0) { $0 + byteCount(of: $1) }
    }

    func removeAll() {
        for digest in allDigests {
            try? fileManager.removeItem(at: directory.appendingPathComponent(digest))
        }
    }

    static func hash(of data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - The on-disk shape of a message

/// A message as stored: the same thing, with attachment *bytes* replaced by a
/// reference to the blob store.
private struct PersistedMessage: Codable {
    struct Attachment: Codable {
        let id: UUID
        let fileName: String
        let mimeType: String
        let digest: String
        let width: Double
        let height: Double
    }

    let id: UUID
    let sender: MessageSender
    let content: String
    let timestamp: Date
    let blocks: [AIContentBlock]
    let attachments: [Attachment]
}

// MARK: - Sessions on disk

/// Saves, lists, and deletes conversations.
@MainActor
final class ChatSessionStore: ObservableObject {

    /// Newest first — the order the history is read in.
    @Published private(set) var summaries: [ChatSessionSummary] = []

    private let root: URL
    private let sessionsDirectory: URL
    private let indexURL: URL
    let attachments: AttachmentStore
    private let fileManager = FileManager.default

    static let shared = ChatSessionStore()

    init(root: URL? = nil) {
        let base = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Markowski/Chats", isDirectory: true)

        self.root = base
        self.sessionsDirectory = base.appendingPathComponent("Sessions", isDirectory: true)
        self.indexURL = base.appendingPathComponent("index.json")
        self.attachments = AttachmentStore(
            directory: base.appendingPathComponent("Attachments", isDirectory: true)
        )

        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        loadIndex()
    }

    // MARK: Reading

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([ChatSessionSummary].self, from: data) else {
            summaries = []
            return
        }
        summaries = stored.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func writeIndex() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(summaries) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func sessionURL(_ id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Reads a whole conversation back, rehydrating its attachments.
    func load(_ id: UUID) -> ChatSession? {
        guard let summary = summaries.first(where: { $0.id == id }),
              let data = try? Data(contentsOf: sessionURL(id)),
              let stored = try? JSONDecoder().decode([PersistedMessage].self, from: data) else {
            return nil
        }

        let messages = stored.map { message -> AIMessage in
            let images = message.attachments.compactMap { attachment -> AIImageAttachment? in
                // A blob that has gone missing must not take the whole
                // conversation with it — the words are the valuable part.
                guard let bytes = attachments.load(attachment.digest) else { return nil }
                return AIImageAttachment(
                    id: attachment.id,
                    fileName: attachment.fileName,
                    mimeType: attachment.mimeType,
                    data: bytes,
                    pixelSize: CGSize(width: attachment.width, height: attachment.height),
                    thumbnail: NSImage(data: bytes)
                )
            }
            return AIMessage(
                id: message.id,
                sender: message.sender,
                content: message.content,
                timestamp: message.timestamp,
                blocks: message.blocks,
                attachments: images
            )
        }

        return ChatSession(
            id: summary.id,
            title: summary.title,
            createdAt: summary.createdAt,
            updatedAt: summary.updatedAt,
            messages: messages
        )
    }

    // MARK: Writing

    /// Saves a conversation. An empty one is not worth a row in the list, so it
    /// is removed rather than stored.
    func save(_ session: ChatSession) {
        guard !session.isEmpty else {
            delete(session.id)
            return
        }

        var stored: [PersistedMessage] = []
        var attachmentCount = 0
        var attachmentBytes = 0

        for message in session.messages {
            let persistedAttachments = message.attachments.map { image -> PersistedMessage.Attachment in
                let digest = attachments.store(image.data)
                attachmentCount += 1
                attachmentBytes += image.data.count
                return PersistedMessage.Attachment(
                    id: image.id,
                    fileName: image.fileName,
                    mimeType: image.mimeType,
                    digest: digest,
                    width: Double(image.pixelSize.width),
                    height: Double(image.pixelSize.height)
                )
            }
            stored.append(PersistedMessage(
                id: message.id,
                sender: message.sender,
                content: message.content,
                timestamp: message.timestamp,
                blocks: message.blocks,
                attachments: persistedAttachments
            ))
        }

        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: sessionURL(session.id), options: .atomic)

        let summary = ChatSessionSummary(
            id: session.id,
            title: session.title == ChatSession.untitled
                ? ChatSession.derivedTitle(from: session.messages)
                : session.title,
            createdAt: session.createdAt,
            updatedAt: Date(),
            messageCount: session.messages.count,
            attachmentCount: attachmentCount,
            attachmentBytes: attachmentBytes
        )

        if let index = summaries.firstIndex(where: { $0.id == session.id }) {
            summaries[index] = summary
        } else {
            summaries.append(summary)
        }
        summaries.sort { $0.updatedAt > $1.updatedAt }
        writeIndex()
    }

    // MARK: Deleting

    /// Removes one chat and every attachment only it was holding on to.
    @discardableResult
    func delete(_ id: UUID) -> Int {
        try? fileManager.removeItem(at: sessionURL(id))
        summaries.removeAll { $0.id == id }
        writeIndex()
        return attachments.collectGarbage(keeping: referencedDigests())
    }

    /// Removes everything: chats, their messages, and all attachment bytes.
    @discardableResult
    func deleteAll() -> Int {
        let freed = attachments.totalBytes
        for summary in summaries {
            try? fileManager.removeItem(at: sessionURL(summary.id))
        }
        summaries = []
        writeIndex()
        attachments.removeAll()
        return freed
    }

    /// Every blob still spoken for by a stored chat.
    func referencedDigests() -> Set<String> {
        var referenced: Set<String> = []
        for summary in summaries {
            guard let data = try? Data(contentsOf: sessionURL(summary.id)),
                  let stored = try? JSONDecoder().decode([PersistedMessage].self, from: data) else {
                continue
            }
            for message in stored {
                for attachment in message.attachments {
                    referenced.insert(attachment.digest)
                }
            }
        }
        return referenced
    }

    // MARK: What it all costs

    struct StorageReport: Equatable {
        var chatCount: Int
        var attachmentBytes: Int
        var orphanedBytes: Int

        var attachmentSizeDescription: String {
            ByteCountFormatter.string(fromByteCount: Int64(attachmentBytes), countStyle: .file)
        }

        var orphanedSizeDescription: String {
            ByteCountFormatter.string(fromByteCount: Int64(orphanedBytes), countStyle: .file)
        }
    }

    func storageReport() -> StorageReport {
        let referenced = referencedDigests()
        return StorageReport(
            chatCount: summaries.count,
            attachmentBytes: attachments.totalBytes,
            orphanedBytes: attachments.orphanedBytes(referenced: referenced)
        )
    }

    /// Sweeps blobs nothing refers to any more.
    @discardableResult
    func reclaimOrphanedAttachments() -> Int {
        attachments.collectGarbage(keeping: referencedDigests())
    }
}
