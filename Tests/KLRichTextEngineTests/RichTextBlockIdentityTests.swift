import Foundation
import Testing
@testable import KLRichTextEngine

@MainActor
@Suite
struct RichTextBlockIdentityTests {
    private let codec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: 100,
            maximumTextUTF8Bytes: 10_000,
            maximumEmbeddedDataBytes: 10_000
        )
    )

    @Test
    func `editing one paragraph preserves every existing block ID`() throws {
        let previous = try makeDocument()
        let value = try #require(
            codec.attributedString(from: previous).mutableCopy() as? NSMutableAttributedString
        )
        value.replaceCharacters(in: try range(of: "Alpha", in: value), with: "Alpha revised")

        let result = try codec.document(from: value, reconciling: previous)

        #expect(result.blocks.map(\.id) == previous.blocks.map(\.id))
    }

    @Test
    func `splitting a paragraph allocates one ID and preserves unaffected IDs`() throws {
        let previous = try makeDocument()
        let value = try #require(
            codec.attributedString(from: previous).mutableCopy() as? NSMutableAttributedString
        )
        let alphaRange = try range(of: "Alpha", in: value)
        value.insert(NSAttributedString(string: "\n"), at: alphaRange.location + 2)

        let result = try codec.document(from: value, reconciling: previous)
        let previousIDs = Set(previous.blocks.map(\.id))
        let newIDs = Set(result.blocks.map(\.id).filter { !previousIDs.contains($0) })

        #expect(result.blocks.count == previous.blocks.count + 1)
        #expect(newIDs.count == 1)
        #expect(result.blocks[0].id == previous.blocks[0].id)
        #expect(result.blocks[2].id == previous.blocks[1].id)
        #expect(result.blocks[3].id == previous.blocks[2].id)
    }

    @Test
    func `merging paragraphs keeps the leading and unaffected block IDs`() throws {
        let previous = try makeDocument()
        let value = try #require(
            codec.attributedString(from: previous).mutableCopy() as? NSMutableAttributedString
        )
        value.deleteCharacters(in: try range(of: "\n", in: value))

        let result = try codec.document(from: value, reconciling: previous)

        #expect(result.blocks.count == 2)
        #expect(result.blocks[0].id == previous.blocks[0].id)
        #expect(result.blocks[1].id == previous.blocks[2].id)
    }

    @Test
    func `inserting before a checklist preserves all prior IDs`() throws {
        let previous = try makeDocument()
        let value = try #require(
            codec.attributedString(from: previous).mutableCopy() as? NSMutableAttributedString
        )
        let checklistRange = try range(of: "Charlie", in: value)
        value.insert(NSAttributedString(string: "Inserted\n"), at: checklistRange.location)

        let result = try codec.document(from: value, reconciling: previous)
        let resultIDs = Set(result.blocks.map(\.id))

        #expect(result.blocks.count == 4)
        #expect(previous.blocks.allSatisfy { resultIDs.contains($0.id) })
        #expect(result.blocks[3].id == previous.blocks[2].id)
    }

    @Test
    func `deleting a block preserves IDs on both sides`() throws {
        let previous = try makeDocument()
        let value = try #require(
            codec.attributedString(from: previous).mutableCopy() as? NSMutableAttributedString
        )
        value.deleteCharacters(in: try range(of: "Bravo\n", in: value))

        let result = try codec.document(from: value, reconciling: previous)

        #expect(result.blocks.map(\.id) == [previous.blocks[0].id, previous.blocks[2].id])
    }

    @Test
    func `duplicate IDs in a public previous document are rejected without crashing`() throws {
        let duplicateID = try #require(
            UUID(uuidString: "40000000-0000-0000-0000-000000000099")
        )
        let previous = RichTextDocument(blocks: [
            .paragraph(
                RichTextParagraph(
                    id: duplicateID,
                    content: RichTextContent(plainText: "First")
                )
            ),
            .paragraph(
                RichTextParagraph(
                    id: duplicateID,
                    content: RichTextContent(plainText: "Second")
                )
            ),
        ])

        #expect(throws: RichTextDocumentCodecError.validationFailure) {
            try codec.document(
                from: NSAttributedString(string: "First\nSecond"),
                reconciling: previous
            )
        }
    }

    private func makeDocument() throws -> RichTextDocument {
        let alphaID = try #require(UUID(uuidString: "40000000-0000-0000-0000-000000000001"))
        let bravoID = try #require(UUID(uuidString: "40000000-0000-0000-0000-000000000002"))
        let charlieID = try #require(UUID(uuidString: "40000000-0000-0000-0000-000000000003"))
        return RichTextDocument(blocks: [
            .paragraph(RichTextParagraph(id: alphaID, content: RichTextContent(plainText: "Alpha"))),
            .paragraph(RichTextParagraph(id: bravoID, content: RichTextContent(plainText: "Bravo"))),
            .checklistItem(
                RichTextChecklistItem(
                    id: charlieID,
                    isChecked: true,
                    content: RichTextContent(plainText: "Charlie")
                )
            ),
        ])
    }

    private func range(of text: String, in value: NSAttributedString) throws -> NSRange {
        let range = (value.string as NSString).range(of: text)
        try #require(range.location != NSNotFound)
        return range
    }
}
