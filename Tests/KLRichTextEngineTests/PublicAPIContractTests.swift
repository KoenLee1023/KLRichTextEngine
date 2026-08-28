import Foundation
import Testing
@testable import KLRichTextEngine

@Suite
struct PublicAPIContractTests {
    @Test(arguments: [
        RichTextChecklistMutationError.itemNotFound(UUID()),
        .invalidUTF16Offset(7),
        .readOnly(.invalidPayload),
    ])
    func `checklist mutation errors retain the original exhaustive switch contract`(
        error: RichTextChecklistMutationError
    ) {
        let category = switch error {
        case .itemNotFound:
            "item"
        case .invalidUTF16Offset:
            "offset"
        case .readOnly:
            "readOnly"
        }

        #expect(["item", "offset", "readOnly"].contains(category))
    }

    @Test
    func `a document containing paragraph and checklist blocks round trips`() throws {
        let paragraphID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let checklistID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let document = RichTextDocument(blocks: [
            .paragraph(
                RichTextParagraph(
                    id: paragraphID,
                    content: RichTextContent(plainText: "Opening")
                )
            ),
            .checklistItem(
                RichTextChecklistItem(
                    id: checklistID,
                    isChecked: true,
                    content: RichTextContent(
                        plainText: "Review",
                        rtfData: Data(#"{\rtf1\ansi \b Review}"#.utf8),
                        fallbackMarkdown: "**Review**",
                        fontStorageMode: .dynamicBodyV1
                    )
                )
            ),
        ])

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(RichTextDocument.self, from: encoded)

        #expect(decoded == document)
        #expect(decoded.plainText == "Opening\nReview")
        #expect(decoded.blocks.map(\.id) == [paragraphID, checklistID])
    }
}
