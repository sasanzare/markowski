import XCTest
@testable import MarkView

/// Stage 4: the assistant proposes *operations against blocks*, not a
/// regenerated file. These hold the line that a scoped edit stays scoped.
final class AIOperationTests: XCTestCase {

    private let sample = """
    # Project README

    One sentence about the project.

    ## Installation

    - brew install thing
    - run it

    | Option | Default |
    | --- | --- |
    | fast | off |
    """

    private func fixture() -> (RichDocument, AIBlockHandles) {
        let document = MarkdownDocumentParser.parse(sample)
        return (document, AIBlockHandles(document: document))
    }

    // MARK: - Addressing

    func testHandlesAreShortStableAndRoundTrip() {
        let (document, handles) = fixture()

        XCTAssertEqual(handles.count, document.blocks.count)
        XCTAssertEqual(handles.id(for: "b1"), document.blocks[0].id)
        XCTAssertEqual(handles.handle(for: document.blocks[2].id), "b3")

        // A model that fumbles the case or pads it still lands.
        XCTAssertEqual(handles.id(for: " B1 "), document.blocks[0].id)
        XCTAssertNil(handles.id(for: "b99"))
    }

    func testPromptListingLabelsEveryBlock() {
        let (document, handles) = fixture()
        let listing = AIDocumentOperations.promptListing(for: document, handles: handles)

        for index in 1...document.blocks.count {
            XCTAssertTrue(listing.contains("[b\(index)]"), "Block b\(index) is not addressable")
        }
        XCTAssertTrue(listing.contains("# Project README"))
        XCTAssertTrue(listing.contains("| Option | Default |"))
    }

    func testEmptyDocumentHasAnExplicitInsertionTarget() {
        let document = MarkdownDocumentParser.parse("")
        let handles = AIBlockHandles(document: document)
        let listing = AIDocumentOperations.promptListing(for: document, handles: handles)

        XCTAssertTrue(listing.contains("EMPTY DOCUMENT"))
        XCTAssertTrue(listing.contains("omit after"))
    }

    // MARK: - Decoding

    func testReplaceBlockTouchesOnlyThatBlock() throws {
        let (document, handles) = fixture()
        let untouched = document.blocks.filter { $0.id != document.blocks[1].id }

        let operations = try AIDocumentOperations.decode(
            [["op": "replaceBlock", "block": "b2", "markdown": "A much shorter sentence."]],
            handles: handles
        )
        let updated = try document.applying(operations)

        XCTAssertEqual(updated.blocks[1].plainText, "A much shorter sentence.")
        XCTAssertEqual(updated.blocks.count, document.blocks.count)
        // Every other block is identical, because nothing else was described.
        for block in untouched {
            XCTAssertTrue(updated.blocks.contains { $0.content == block.content })
        }
        // And identity survives, so a follow-up operation still lands.
        XCTAssertEqual(updated.blocks[1].id, document.blocks[1].id)
    }

    func testOneInsertOperationCreatesACompleteEmptyDocumentInOrder() throws {
        let document = MarkdownDocumentParser.parse("")
        let handles = AIBlockHandles(document: document)
        let markdown = """
        # Diagram

        ```mermaid
        graph TD
          A --> B
        ```

        ## Python Test

        ```python
        for i in range(1, 5):
            print(i)
        ```
        """

        let operations = try AIDocumentOperations.decode(
            [["op": "insertBlock", "markdown": markdown]],
            handles: handles
        )
        let updated = try document.applying(operations)

        XCTAssertEqual(updated.blocks.count, 4)
        XCTAssertEqual(updated.blocks[0].plainText, "Diagram")
        XCTAssertEqual(updated.blocks[1].plainText, "graph TD\n  A --> B")
        XCTAssertEqual(updated.blocks[2].plainText, "Python Test")
        XCTAssertEqual(updated.blocks[3].plainText, "for i in range(1, 5):\n    print(i)")
        XCTAssertEqual(MarkdownDocumentSerializer.serialize(updated), markdown + "\n")
    }

    func testEveryOperationDecodes() throws {
        let (document, handles) = fixture()
        let tableHandle = handles.handle(for: document.blocks[4].id) ?? "b5"

        let raw: [[String: Any]] = [
            ["op": "setHeadingLevel", "block": "b1", "level": 2],
            ["op": "insertBlock", "after": "b2", "markdown": "## A new section"],
            ["op": "convertToList", "block": "b2", "style": "ordered"],
            ["op": "setCell", "block": tableHandle, "row": 1, "column": 1, "markdown": "on"],
            ["op": "insertTableRow", "block": tableHandle, "at": 1],
            ["op": "setColumnAlignment", "block": tableHandle, "column": 0, "alignment": "right"]
        ]

        let operations = try AIDocumentOperations.decode(raw, handles: handles)
        XCTAssertEqual(operations.count, 6)

        let updated = try document.applying(operations)
        guard case .heading(let level, _) = updated.blocks[0].content else {
            return XCTFail("Expected a heading")
        }
        XCTAssertEqual(level, 2)

        // The result is still a valid document that round-trips.
        let markdown = MarkdownDocumentSerializer.serialize(updated)
        XCTAssertTrue(MarkdownDocumentParser.parse(markdown).hasSameContent(as: updated))
    }

    func testDeleteAndMoveAddressBlocksByHandle() throws {
        let (document, handles) = fixture()
        let originalCount = document.blocks.count

        let operations = try AIDocumentOperations.decode(
            [["op": "deleteBlock", "block": "b2"]],
            handles: handles
        )
        XCTAssertEqual(try document.applying(operations).blocks.count, originalCount - 1)

        let move = try AIDocumentOperations.decode(
            [["op": "moveBlock", "block": "b1", "toIndex": 2]],
            handles: handles
        )
        let moved = try document.applying(move)
        XCTAssertEqual(moved.blocks[2].plainText, "Project README")
    }

    // MARK: - Refusing what can't land

    func testAnInventedHandleIsRefused() {
        let (_, handles) = fixture()
        XCTAssertThrowsError(
            try AIDocumentOperations.decode(
                [["op": "replaceBlock", "block": "b42", "markdown": "x"]],
                handles: handles
            )
        ) { error in
            XCTAssertEqual(error as? AIOperationError, .unknownHandle("b42"))
        }
    }

    func testAnUnknownOperationIsRefused() {
        let (_, handles) = fixture()
        XCTAssertThrowsError(
            try AIDocumentOperations.decode([["op": "reformatEverything"]], handles: handles)
        ) { error in
            XCTAssertEqual(error as? AIOperationError, .unknownOperation("reformatEverything"))
        }
    }

    func testAMissingFieldIsRefused() {
        let (_, handles) = fixture()
        XCTAssertThrowsError(
            try AIDocumentOperations.decode([["op": "replaceBlock", "block": "b1"]], handles: handles)
        ) { error in
            XCTAssertEqual(error as? AIOperationError, .missingField(operation: "replaceBlock", field: "markdown"))
        }
        XCTAssertThrowsError(try AIDocumentOperations.decode([], handles: handles)) { error in
            XCTAssertEqual(error as? AIOperationError, .empty)
        }
    }

    /// A batch that fails part way must leave the document untouched — a
    /// half-applied assistant edit is worse than a refused one.
    func testAFailingBatchLeavesTheDocumentAlone() throws {
        let (document, handles) = fixture()

        let operations = try AIDocumentOperations.decode(
            [
                ["op": "replaceBlock", "block": "b2", "markdown": "Changed."],
                // A table operation aimed at a paragraph.
                ["op": "insertTableRow", "block": "b2", "at": 0]
            ],
            handles: handles
        )

        XCTAssertThrowsError(try document.applying(operations))
        XCTAssertEqual(document.blocks[1].plainText, "One sentence about the project.")
    }

    // MARK: - Describing the change

    func testChangesAreDescribedInTheUsersTerms() throws {
        let (document, handles) = fixture()
        let operations = try AIDocumentOperations.decode(
            [
                ["op": "replaceBlock", "block": "b2", "markdown": "Shorter."],
                ["op": "setHeadingLevel", "block": "b1", "level": 3],
                ["op": "deleteBlock", "block": "b3"]
            ],
            handles: handles
        )

        let descriptions = operations.map {
            AIDocumentOperations.describe($0, in: document, handles: handles)
        }

        XCTAssertTrue(descriptions[0].hasPrefix("Rewrite paragraph"))
        XCTAssertTrue(descriptions[0].contains("One sentence about"))
        XCTAssertTrue(descriptions[1].contains("level 3 heading"))
        XCTAssertTrue(descriptions[2].hasPrefix("Delete heading 2"))
    }

    // MARK: - The prompt

    func testPromptAsksForOperationsAndNotAWholeDocument() {
        let (document, handles) = fixture()
        let instruction = AIPromptBuilder.systemInstruction(
            documentText: sample,
            selectedText: nil,
            documentType: "md",
            blockListing: AIDocumentOperations.promptListing(for: document, handles: handles)
        )

        XCTAssertTrue(instruction.contains("document_operations"))
        XCTAssertTrue(instruction.contains("replaceBlock"))
        XCTAssertTrue(instruction.contains("[b1]"), "The model must be shown the handles it may address")
        XCTAssertTrue(
            instruction.contains("A block you do not mention is left exactly as it is"),
            "The scoping rule is the whole point"
        )
        XCTAssertFalse(
            instruction.contains("\"updated_document\": \"The complete modified document\""),
            "The whole-document contract is gone"
        )
        XCTAssertTrue(instruction.contains("You CAN edit an empty document"))
        XCTAssertTrue(instruction.contains("Never ask the user to add a starter line"))
    }
}
