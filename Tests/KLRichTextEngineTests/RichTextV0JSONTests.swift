import Foundation
import Testing
@testable import KLRichTextEngine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite
struct RichTextV0JSONTests {
    private let codec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: 3,
            maximumTextUTF8Bytes: 256,
            maximumEmbeddedDataBytes: 512
        )
    )

    @Test
    func `v0 plain fixture structurally round trips without adding a schema version`() throws {
        let fixture = try fixtureData(named: "v0-plain")
        let result = codec.loadJSON(fixture, fallbackPlainText: "fallback")

        #expect(result.access == .editable)
        #expect(result.originalData == fixture)
        #expect(result.document.plainText == "A synthetic paragraph")

        let encoded = try codec.encodeJSON(result.document, version: .v0)
        #expect(try canonicalJSON(encoded) == canonicalJSON(fixture))
        let block = try firstBlockObject(in: encoded)
        let paragraph = try #require(block["paragraph"] as? [String: Any])
        #expect(paragraph["text"] != nil)
        #expect(paragraph["content"] == nil)
        #expect(block["text"] == nil)
    }

    @Test
    func `v0 checklist fixture preserves semantic state and authored payload`() throws {
        let fixture = try fixtureData(named: "v0-checklist")
        let result = codec.loadJSON(fixture, fallbackPlainText: "fallback")

        #expect(result.access == .editable)
        let block = try #require(result.document.blocks.first)
        guard case let .checklistItem(item) = block else {
            Issue.record("Expected a checklist item")
            return
        }
        #expect(item.isChecked)
        #expect(item.content.fallbackMarkdown == "~~Inspect~~ the synthetic fixture")
        let attributed = RichTextRTFCodec().attributedString(from: item.content)
        #expect(attributed.string == item.content.plainText)
        #expect(
            attributed.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
                == NSUnderlineStyle.single.rawValue
        )

        let encoded = try codec.encodeJSON(result.document, version: .v0)
        #expect(try canonicalJSON(encoded) == canonicalJSON(fixture))
        let blockObject = try firstBlockObject(in: encoded)
        let checklist = try #require(blockObject["checklist"] as? [String: Any])
        #expect(checklist["text"] != nil)
        #expect(checklist["content"] == nil)
        #expect(blockObject["text"] == nil)
    }

    @Test
    func `production shaped v0 bytes load editable and structurally object round trip`() throws {
        let productionShapedBytes = Data(
            #"{"blocks":[{"type":"paragraph","paragraph":{"id":"11000000-0000-0000-0000-000000000001","text":{"plainText":"Production-shaped synthetic"}}},{"type":"checklist","checklist":{"id":"21000000-0000-0000-0000-000000000001","isChecked":false,"text":{"plainText":"Independent task","fallbackMarkdown":"**Independent** task","fontStorageMode":"dynamicBodyV1"}}}]}"#.utf8
        )

        let result = codec.loadJSON(productionShapedBytes, fallbackPlainText: "fallback")

        #expect(result.access == .editable)
        #expect(result.document.plainText == "Production-shaped synthetic\nIndependent task")
        let directlyEncoded = try JSONEncoder().encode(result.document)
        #expect(
            try canonicalJSON(directlyEncoded) == canonicalJSON(productionShapedBytes)
        )
    }

    @Test
    func `unknown font storage mode remains structurally preserved and read only`() throws {
        let fixture = try fixtureData(named: "v0-unknown-font-mode")
        let result = codec.loadJSON(fixture, fallbackPlainText: "fallback")

        #expect(result.access == .readOnly(.unknownFontStorageMode("semanticBodyV99")))
        #expect(result.originalData == fixture)
        #expect(result.document.hasUnknownFontStorageMode)

        #expect(throws: RichTextDocumentCodecError.readOnly(
            .unknownFontStorageMode("semanticBodyV99")
        )) {
            try codec.encodeJSON(result.document, version: .v0)
        }
    }

    @Test
    func `unknown schema returns fallback document and preserves every original byte`() throws {
        let fixture = try fixtureData(named: "v99-unknown-schema")
        let result = codec.loadJSON(fixture, fallbackPlainText: "Safe fallback")

        #expect(result.access == .readOnly(.unknownSchema(99)))
        #expect(result.originalData == fixture)
        #expect(result.document.plainText == "Safe fallback")
    }

    @Test
    func `v1 encoding is deterministic and explicitly versioned`() throws {
        let fixture = try fixtureData(named: "v0-plain")
        let document = codec.loadJSON(fixture, fallbackPlainText: "fallback").document

        let first = try codec.encodeJSON(document, version: .v1)
        let second = try codec.encodeJSON(document, version: .v1)
        let object = try #require(JSONSerialization.jsonObject(with: first) as? [String: Any])

        #expect(first == second)
        #expect(object["schemaVersion"] as? Int == 1)
    }

    @Test(arguments: [0, 1, 2])
    func `caller policy rejects each resource limit`(limitIndex: Int) throws {
        let document: RichTextDocument
        switch limitIndex {
        case 0:
            document = RichTextDocument(
                blocks: (0 ..< 4).map { index in
                    .paragraph(
                        RichTextParagraph(
                            id: UUID(),
                            content: RichTextContent(plainText: "Block \(index)")
                        )
                    )
                }
            )
        case 1:
            document = RichTextDocument(
                blocks: [
                    .paragraph(
                        RichTextParagraph(
                            id: UUID(),
                            content: RichTextContent(plainText: String(repeating: "a", count: 257))
                        )
                    ),
                ]
            )
        default:
            document = RichTextDocument(
                blocks: [
                    .paragraph(
                        RichTextParagraph(
                            id: UUID(),
                            content: RichTextContent(
                                plainText: "embedded",
                                rtfData: Data(repeating: 0xAB, count: 513)
                            )
                        )
                    ),
                ]
            )
        }

        let data = try JSONEncoder().encode(document)
        let result = codec.loadJSON(data, fallbackPlainText: "Limit fallback")

        #expect(result.access == .readOnly(.validationFailure))
        #expect(result.originalData == data)
        #expect(result.document.plainText == "Limit fallback")
    }

    @Test
    func `malformed payload is read only and retains original data`() {
        let data = Data("{not-json".utf8)
        let result = codec.loadJSON(data, fallbackPlainText: "Malformed fallback")

        #expect(result.access == .readOnly(.invalidPayload))
        #expect(result.originalData == data)
        #expect(result.document.plainText == "Malformed fallback")
    }

    @Test
    func `duplicate block IDs decode as a validation failure`() throws {
        let id = try #require(UUID(uuidString: "60000000-0000-0000-0000-000000000001"))
        let document = RichTextDocument(blocks: [
            .paragraph(RichTextParagraph(id: id, content: RichTextContent(plainText: "First"))),
            .paragraph(RichTextParagraph(id: id, content: RichTextContent(plainText: "Second"))),
        ])
        let data = try JSONEncoder().encode(document)

        let result = codec.loadJSON(data, fallbackPlainText: "Duplicate fallback")

        #expect(result.access == .readOnly(.validationFailure))
        #expect(result.originalData == data)
    }

    @Test
    func `duplicate block IDs cannot be encoded by the codec`() throws {
        let id = try #require(UUID(uuidString: "60000000-0000-0000-0000-000000000002"))
        let document = RichTextDocument(blocks: [
            .paragraph(RichTextParagraph(id: id, content: RichTextContent(plainText: "First"))),
            .paragraph(RichTextParagraph(id: id, content: RichTextContent(plainText: "Second"))),
        ])

        #expect(throws: RichTextDocumentCodecError.validationFailure) {
            try codec.encodeJSON(document, version: .v1)
        }
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func canonicalJSON(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func firstBlockObject(in data: Data) throws -> [String: Any] {
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let blocks = try #require(object["blocks"] as? [[String: Any]])
        return try #require(blocks.first)
    }
}
