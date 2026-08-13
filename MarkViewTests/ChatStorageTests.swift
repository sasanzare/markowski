import XCTest
import AppKit
import SwiftUI
@testable import MarkView

/// Chats hold the heaviest thing the app stores — attachment bytes — so these
/// check the two properties that make that manageable: identical files are
/// stored once, and deleting a chat actually gives the disk space back.
@MainActor
final class ChatStorageTests: XCTestCase {

    private var root: URL!
    private var store: ChatSessionStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("markowski-chats-\(UUID().uuidString)")
        store = ChatSessionStore(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helpers

    private func image(_ seed: String) -> AIImageAttachment {
        let data = Data(seed.utf8) + Data(repeating: 0xAB, count: 2048)
        return AIImageAttachment(
            fileName: "\(seed).png",
            mimeType: "image/png",
            data: data,
            pixelSize: CGSize(width: 10, height: 10),
            thumbnail: nil
        )
    }

    private func session(
        title: String = ChatSession.untitled,
        text: String = "Hello",
        images: [AIImageAttachment] = []
    ) -> ChatSession {
        ChatSession(
            title: title,
            messages: [
                AIMessage(sender: .user, content: text, attachments: images),
                AIMessage(sender: .assistant, content: "Sure.")
            ]
        )
    }

    // MARK: - Round trip

    func testSavingAndLoadingKeepsMessagesAndImages() throws {
        let picture = image("shot")
        let saved = session(text: "What is in this picture?", images: [picture])
        store.save(saved)

        let loaded = try XCTUnwrap(store.load(saved.id))
        XCTAssertEqual(loaded.messages.count, 2)
        XCTAssertEqual(loaded.messages[0].content, "What is in this picture?")
        XCTAssertEqual(loaded.messages[0].attachments.count, 1)
        XCTAssertEqual(loaded.messages[0].attachments[0].data, picture.data)
        XCTAssertEqual(loaded.messages[0].attachments[0].fileName, "shot.png")
    }

    func testTitleComesFromTheFirstThingAsked() {
        let saved = session(text: "Summarise the Q3 report\nsecond line")
        store.save(saved)

        XCTAssertEqual(store.summaries.first?.title, "Summarise the Q3 report")
    }

    func testAnEmptyChatIsNotStored() {
        store.save(ChatSession())
        XCTAssertTrue(store.summaries.isEmpty, "An empty chat has nothing to list")
    }

    func testSummariesAreNewestFirst() {
        let older = session(text: "first")
        store.save(older)
        let newer = session(text: "second")
        store.save(newer)

        XCTAssertEqual(store.summaries.map(\.title), ["second", "first"])
    }

    // MARK: - The cache

    /// The same file in two chats must cost one file on disk. Without this,
    /// pasting one screenshot into five conversations quietly costs five times
    /// what it should.
    func testTheSameImageInTwoChatsIsStoredOnce() {
        let picture = image("identical")
        store.save(session(text: "one", images: [picture]))
        store.save(session(text: "two", images: [picture]))

        XCTAssertEqual(store.summaries.count, 2)
        XCTAssertEqual(
            store.attachments.allDigests.count, 1,
            "Identical bytes should share a single blob"
        )
    }

    func testDifferentImagesAreStoredSeparately() {
        store.save(session(text: "one", images: [image("a")]))
        store.save(session(text: "two", images: [image("b")]))
        XCTAssertEqual(store.attachments.allDigests.count, 2)
    }

    /// Deleting a chat has to take its bytes with it, or "delete" is cosmetic
    /// and the disk fills up with things the user believes they removed.
    func testDeletingAChatReclaimsItsAttachmentBytes() throws {
        let saved = session(text: "with a picture", images: [image("only")])
        store.save(saved)
        XCTAssertGreaterThan(store.attachments.totalBytes, 0)

        let freed = store.delete(saved.id)

        XCTAssertGreaterThan(freed, 0, "Deleting should report what it freed")
        XCTAssertTrue(store.summaries.isEmpty)
        XCTAssertEqual(store.attachments.totalBytes, 0, "No bytes may be left behind")
        XCTAssertNil(store.load(saved.id))
    }

    /// …but only the bytes nothing else is using.
    func testDeletingOneChatKeepsAnImageAnotherChatStillUses() throws {
        let shared = image("shared")
        let first = session(text: "one", images: [shared])
        let second = session(text: "two", images: [shared])
        store.save(first)
        store.save(second)

        store.delete(first.id)

        XCTAssertEqual(store.attachments.allDigests.count, 1, "The survivor still needs it")
        let survivor = try XCTUnwrap(store.load(second.id))
        XCTAssertEqual(survivor.messages[0].attachments.first?.data, shared.data)
    }

    func testDeleteAllRemovesEveryChatAndEveryByte() {
        store.save(session(text: "one", images: [image("a")]))
        store.save(session(text: "two", images: [image("b")]))

        let freed = store.deleteAll()

        XCTAssertGreaterThan(freed, 0)
        XCTAssertTrue(store.summaries.isEmpty)
        XCTAssertEqual(store.attachments.totalBytes, 0)
        XCTAssertTrue(store.attachments.allDigests.isEmpty)
    }

    func testStorageReportCountsWhatIsActuallyThere() {
        store.save(session(text: "one", images: [image("a"), image("b")]))

        let report = store.storageReport()
        XCTAssertEqual(report.chatCount, 1)
        XCTAssertGreaterThan(report.attachmentBytes, 0)
        XCTAssertEqual(report.orphanedBytes, 0, "Everything here is still referenced")
    }

    /// A blob left behind by an interrupted save belongs to nobody and should
    /// be sweepable without touching any conversation.
    func testOrphanedBlobsAreReportedAndReclaimable() {
        store.save(session(text: "kept", images: [image("kept")]))
        let strayDigest = store.attachments.store(Data(repeating: 0x11, count: 4096))

        XCTAssertTrue(store.attachments.exists(strayDigest))
        XCTAssertGreaterThan(store.storageReport().orphanedBytes, 0)

        let freed = store.reclaimOrphanedAttachments()

        XCTAssertGreaterThan(freed, 0)
        XCTAssertFalse(store.attachments.exists(strayDigest))
        XCTAssertEqual(store.storageReport().orphanedBytes, 0)
        XCTAssertEqual(store.summaries.count, 1, "Sweeping must not disturb the chats")
    }

    func testSavingTheSameChatTwiceDoesNotDuplicateIt() {
        var saved = session(text: "first version")
        store.save(saved)
        saved.messages.append(AIMessage(sender: .user, content: "more"))
        store.save(saved)

        XCTAssertEqual(store.summaries.count, 1)
        XCTAssertEqual(store.summaries.first?.messageCount, 3)
    }

    /// Chats have to survive the app closing, which is the whole point of
    /// storing them.
    func testChatsSurviveAFreshStore() throws {
        let saved = session(text: "remember me", images: [image("keep")])
        store.save(saved)

        let reopened = ChatSessionStore(root: root)
        XCTAssertEqual(reopened.summaries.count, 1)
        XCTAssertEqual(reopened.summaries.first?.title, "remember me")

        let loaded = try XCTUnwrap(reopened.load(saved.id))
        XCTAssertEqual(loaded.messages[0].attachments.count, 1)
    }

    /// A missing blob must cost you the picture, not the conversation.
    func testAChatStillOpensIfAnAttachmentWentMissing() throws {
        let saved = session(text: "text matters most", images: [image("gone")])
        store.save(saved)
        store.attachments.removeAll()

        let loaded = try XCTUnwrap(store.load(saved.id))
        XCTAssertEqual(loaded.messages[0].content, "text matters most")
        XCTAssertTrue(loaded.messages[0].attachments.isEmpty)
    }

    // MARK: - What the sidebar drives

    /// The service's own lifecycle, since that is what the New Chat button and
    /// the history rows actually call.
    func testNewChatFilesTheOldOneAndStartsEmpty() {
        let service = AIService(sessions: store)
        service.conversation = [
            AIMessage(sender: .user, content: "first question"),
            AIMessage(sender: .assistant, content: "an answer")
        ]
        let firstID = service.currentSessionID

        service.startNewChat()

        XCTAssertTrue(service.conversation.isEmpty, "The new chat starts blank")
        XCTAssertNotEqual(service.currentSessionID, firstID)
        XCTAssertEqual(store.summaries.count, 1, "The old chat was filed, not lost")
        XCTAssertEqual(store.summaries.first?.title, "first question")
    }

    func testOpeningAChatBringsItBack() throws {
        let service = AIService(sessions: store)
        service.conversation = [AIMessage(sender: .user, content: "remember this")]
        let firstID = service.currentSessionID
        service.startNewChat()

        service.openChat(firstID)

        XCTAssertEqual(service.currentSessionID, firstID)
        XCTAssertEqual(service.conversation.first?.content, "remember this")
    }

    /// Reading a chat is not a change to it — it must not jump to the top of
    /// the list just for having been opened.
    func testOpeningAChatDoesNotReorderTheHistory() {
        let service = AIService(sessions: store)
        service.conversation = [AIMessage(sender: .user, content: "older")]
        let olderID = service.currentSessionID
        service.startNewChat()
        service.conversation = [AIMessage(sender: .user, content: "newer")]
        service.startNewChat()

        XCTAssertEqual(store.summaries.map(\.title), ["newer", "older"])
        service.openChat(olderID)
        XCTAssertEqual(store.summaries.map(\.title), ["newer", "older"], "Order must be unchanged")
    }

    func testDeletingTheOpenChatClearsTheScreen() {
        let service = AIService(sessions: store)
        service.conversation = [AIMessage(sender: .user, content: "goodbye")]
        let id = service.currentSessionID

        service.deleteChat(id)

        XCTAssertTrue(service.conversation.isEmpty)
        XCTAssertTrue(store.summaries.isEmpty)
        XCTAssertNotEqual(service.currentSessionID, id)
    }

    func testDeleteAllChatsClearsScreenAndDisk() {
        let service = AIService(sessions: store)
        service.conversation = [AIMessage(sender: .user, content: "one", attachments: [image("x")])]
        service.startNewChat()
        service.conversation = [AIMessage(sender: .user, content: "two")]

        service.deleteAllChats()

        XCTAssertTrue(service.conversation.isEmpty)
        XCTAssertTrue(store.summaries.isEmpty)
        XCTAssertEqual(store.attachments.totalBytes, 0)
    }

    func testEachReplyKeepsTheStoredChatUpToDate() {
        let service = AIService(sessions: store)
        service.conversation = [AIMessage(sender: .user, content: "q")]
        XCTAssertEqual(store.summaries.first?.messageCount, 1)

        service.conversation.append(AIMessage(sender: .assistant, content: "a"))
        XCTAssertEqual(
            store.summaries.first?.messageCount, 2,
            "Saving is driven by the conversation itself, so replies are covered too"
        )
    }

    // MARK: - The header these buttons live in

    /// The assistant header put a centred title behind right-pinned controls,
    /// so adding the chat buttons pushed them straight through the wordmark.
    /// The row is an `HStack` now and cannot overlap itself — but it can still
    /// get too wide, so this pins the control budget: three buttons must leave
    /// room for the icon and title inside the narrowest inspector.
    func testHeaderControlsLeaveRoomForTheTitle() {
        let controls = HStack(spacing: 2) {
            AssistantHeaderButton(symbol: "square.and.pencil", help: "New chat") {}
            AssistantHeaderButton(symbol: "clock.arrow.circlepath", help: "History") {}
            AssistantHeaderButton(symbol: "gearshape", help: "Settings") {}
        }

        let hosting = NSHostingView(rootView: controls)
        hosting.layoutSubtreeIfNeeded()
        let width = hosting.fittingSize.width

        XCTAssertGreaterThan(width, 0)

        // The inspector never goes below 320pt. Leave the icon (30), the
        // wordmark (~90), the paddings (24) and a gap — so the controls have
        // roughly 150pt before something has to give.
        XCTAssertLessThan(
            width, 150,
            "Header controls grew to \(width)pt and will start crowding the title"
        )
    }

    func testADisabledHeaderButtonDoesNotFire() {
        var fired = false
        let button = AssistantHeaderButton(
            symbol: "square.and.pencil",
            help: "New chat",
            isEnabled: false
        ) { fired = true }

        let hosting = NSHostingView(rootView: button)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertFalse(fired, "Nothing should have run just from building it")
        XCTAssertGreaterThan(hosting.fittingSize.width, 0)
    }

    func testHashingIsContentAddressed() {
        let a = AttachmentStore.hash(of: Data("same".utf8))
        let b = AttachmentStore.hash(of: Data("same".utf8))
        let c = AttachmentStore.hash(of: Data("different".utf8))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
