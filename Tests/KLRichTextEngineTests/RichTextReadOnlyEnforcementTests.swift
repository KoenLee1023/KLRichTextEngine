import Foundation
import Testing
@testable import KLRichTextEngine

enum ReadOnlyFixture: CaseIterable, Sendable {
    case unknownSchema
    case unknownFont

    var name: String {
        switch self {
        case .unknownSchema: "v99-unknown-schema"
        case .unknownFont: "v0-unknown-font-mode"
        }
    }

    var reason: RichTextReadOnlyReason {
        switch self {
        case .unknownSchema: .unknownSchema(99)
        case .unknownFont: .unknownFontStorageMode("semanticBodyV99")
        }
    }
}

enum ReadOnlyAttributedEdit: CaseIterable, Sendable {
    case copyOnly
    case prependUnannotatedText
    case appendUnannotatedText
    case replaceLeadingRange
    case deletePartialRange
    case replaceEveryOriginalRange
    case deleteEveryOriginalRangeAfterPrependingText
    case stripAllAttributes
    case emptyAllContent
}

@MainActor
@Suite
struct RichTextReadOnlyEnforcementTests {
    private let codec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: 8,
            maximumTextUTF8Bytes: 1_024,
            maximumEmbeddedDataBytes: 4_096
        )
    )

    @Test
    func `unknown schema cannot be encoded and retains its exact source bytes`() throws {
        let source = try fixtureData(named: "v99-unknown-schema")
        let result = codec.loadJSON(source, fallbackPlainText: "Visible fallback")

        #expect(result.originalData == source)
        #expect(throws: RichTextDocumentCodecError.readOnly(.unknownSchema(99))) {
            try codec.encodeJSON(result.document, version: .v1)
        }
        #expect(result.originalData == source)
    }

    @Test
    func `unknown font document cannot be encoded or replaced from attributed text`() throws {
        let source = try fixtureData(named: "v0-unknown-font-mode")
        let result = codec.loadJSON(source, fallbackPlainText: "fallback")
        let reason = RichTextReadOnlyReason.unknownFontStorageMode("semanticBodyV99")

        #expect(result.originalData == source)
        #expect(throws: RichTextDocumentCodecError.readOnly(reason)) {
            try codec.encodeJSON(result.document, version: .v0)
        }
        #expect(throws: RichTextDocumentCodecError.readOnly(reason)) {
            try codec.document(
                from: NSAttributedString(string: "replacement"),
                reconciling: result.document
            )
        }
        #expect(result.originalData == source)
    }

    @Test
    func `public checklist mutations reject a read only document`() throws {
        let itemID = try #require(UUID(uuidString: "61000000-0000-0000-0000-000000000001"))
        let source = Data("future-schema-source".utf8)
        let loaded = RichTextDocumentLoadResult(
            document: RichTextDocument(
                blocks: [
                    .checklistItem(
                        RichTextChecklistItem(
                            id: itemID,
                            isChecked: false,
                            content: RichTextContent(plainText: "Protected")
                        )
                    ),
                ]
            ),
            access: .readOnly(.unknownSchema(99)),
            originalData: source
        )
        let mutation = RichTextChecklistMutation()

        #expect(throws: RichTextChecklistMutationError.readOnly(.unknownSchema(99))) {
            try mutation.togglingItem(id: itemID, in: loaded.document)
        }
        #expect(throws: RichTextChecklistMutationError.readOnly(.unknownSchema(99))) {
            try mutation.pressingReturn(
                inItemWithID: itemID,
                atUTF16Offset: 3,
                in: loaded.document
            )
        }
        #expect(loaded.originalData == source)
    }

    @Test(arguments: [
        ("v99-unknown-schema", "schema fallback"),
        ("v0-unknown-font-mode", "font fallback"),
    ])
    func `direct JSONEncoder cannot strip loaded read only provenance`(
        fixtureName: String,
        fallback: String
    ) throws {
        let source = try fixtureData(named: fixtureName)
        let loaded = codec.loadJSON(source, fallbackPlainText: fallback)

        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode(loaded.document)
        }
        #expect(loaded.originalData == source)
    }

    @MainActor
    @Test
    func `copied attributed runtime token rejects parse with no previous document`() throws {
        let source = try fixtureData(named: "v0-unknown-font-mode")
        let loaded = codec.loadJSON(source, fallbackPlainText: "fallback")
        let rendered = try codec.attributedString(from: loaded.document)
        let callerCopy = NSAttributedString(attributedString: rendered)

        #expect(throws: RichTextDocumentCodecError.readOnly(
            .unknownFontStorageMode("semanticBodyV99")
        )) {
            try codec.document(from: callerCopy, reconciling: nil)
        }
        #expect(loaded.originalData == source)
    }

    @Test(arguments: ReadOnlyFixture.allCases, ReadOnlyAttributedEdit.allCases)
    func `read only provenance denies parsing after ordinary attributed edits`(
        fixture: ReadOnlyFixture,
        edit: ReadOnlyAttributedEdit
    ) throws {
        let source = try fixtureData(named: fixture.name)
        let loaded = codec.loadJSON(source, fallbackPlainText: "protected fallback")
        let rendered = try codec.attributedString(from: loaded.document)
        let edited = NSMutableAttributedString(attributedString: rendered)

        apply(edit, to: edited)

        let expectedError = expectedError(for: edit, fixture: fixture)
        #expect(throws: expectedError) {
            try codec.document(from: edited, reconciling: nil)
        }
        #expect(loaded.originalData == source)
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode(loaded.document)
        }
    }

    @Test(arguments: ReadOnlyFixture.allCases)
    func `object metadata denies destructive edits even when no characters remain`(
        fixture: ReadOnlyFixture
    ) throws {
        let source = try fixtureData(named: fixture.name)
        let loaded = codec.loadJSON(source, fallbackPlainText: "protected fallback")
        let rendered = try codec.attributedString(from: loaded.document)
        let edited = try #require(rendered as? NSMutableAttributedString)
        edited.deleteCharacters(in: NSRange(location: 0, length: edited.length))

        #expect(throws: RichTextDocumentCodecError.readOnly(fixture.reason)) {
            try codec.document(from: edited, reconciling: nil)
        }
        #expect(loaded.originalData == source)
    }

    @Test
    func `missing attributed provenance with no previous document fails closed`() {
        #expect(throws: RichTextDocumentCodecError.validationFailure) {
            try codec.document(
                from: NSAttributedString(string: "Unprovenanced host value"),
                reconciling: nil
            )
        }
    }

    @Test
    func `editable previous document permits an unprovenanced host edit`() throws {
        let blockID = try #require(
            UUID(uuidString: "72000000-0000-0000-0000-000000000001")
        )
        let previous = RichTextDocument(
            blocks: [
                .paragraph(
                    RichTextParagraph(
                        id: blockID,
                        content: RichTextContent(plainText: "Before host edit")
                    )
                ),
            ]
        )

        let result = try codec.document(
            from: NSAttributedString(string: "After host edit"),
            reconciling: previous
        )

        #expect(result.plainText == "After host edit")
        #expect(result.blocks.map(\.id) == [blockID])
    }

    @Test(arguments: ReadOnlyFixture.allCases)
    func `read only previous document always rejects host attributed edits`(
        fixture: ReadOnlyFixture
    ) throws {
        let source = try fixtureData(named: fixture.name)
        let loaded = codec.loadJSON(source, fallbackPlainText: "protected fallback")

        #expect(throws: RichTextDocumentCodecError.readOnly(fixture.reason)) {
            try codec.document(
                from: NSAttributedString(string: "Host replacement"),
                reconciling: loaded.document
            )
        }
    }

    @Test
    func `explicit factory permits new editable attributed content`() throws {
        let rawValue = NSAttributedString(string: "New editable content")

        let editableValue = try codec.editableAttributedString(from: rawValue)
        let callerCopy = NSAttributedString(attributedString: editableValue)
        let document = try codec.document(from: callerCopy, reconciling: nil)

        #expect(document.plainText == "New editable content")
        _ = try codec.encodeJSON(document, version: .v0)
    }

    @Test
    func `explicit factory preserves a logical empty paragraph through copying`() throws {
        let editableValue = try codec.editableAttributedString(
            from: NSAttributedString(string: "")
        )
        let callerCopy = NSAttributedString(attributedString: editableValue)

        let document = try codec.document(from: callerCopy, reconciling: nil)

        #expect(document.blocks.count == 1)
        #expect(document.plainText.isEmpty)
        guard case .paragraph = document.blocks[0] else {
            Issue.record("Expected a logical empty paragraph")
            return
        }
    }

    @Test(arguments: ReadOnlyFixture.allCases)
    func `explicit editable factory cannot relabel read only package output`(
        fixture: ReadOnlyFixture
    ) throws {
        let source = try fixtureData(named: fixture.name)
        let loaded = codec.loadJSON(source, fallbackPlainText: "protected fallback")
        let rendered = try codec.attributedString(from: loaded.document)

        #expect(throws: RichTextDocumentCodecError.readOnly(fixture.reason)) {
            try codec.editableAttributedString(from: rendered)
        }
    }

    @Test
    func `codec generated editable values remain parseable without previous state`() throws {
        let documents = [
            RichTextDocument(
                blocks: [
                    .paragraph(
                        RichTextParagraph(
                            id: try #require(
                                UUID(uuidString: "73000000-0000-0000-0000-000000000001")
                            ),
                            content: RichTextContent(plainText: "Editable paragraph")
                        )
                    ),
                ]
            ),
            RichTextDocument(
                blocks: [
                    .paragraph(
                        RichTextParagraph(
                            id: try #require(
                                UUID(uuidString: "73000000-0000-0000-0000-000000000002")
                            ),
                            content: RichTextContent(plainText: "")
                        )
                    ),
                ]
            ),
            RichTextDocument(
                blocks: [
                    .checklistItem(
                        RichTextChecklistItem(
                            id: try #require(
                                UUID(uuidString: "73000000-0000-0000-0000-000000000003")
                            ),
                            isChecked: true,
                            content: RichTextContent(plainText: "")
                        )
                    ),
                ]
            ),
        ]

        for document in documents {
            let rendered = try codec.attributedString(from: document)
            let callerCopy = NSAttributedString(attributedString: rendered)

            #expect(try codec.document(from: callerCopy, reconciling: nil) == document)
        }
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func apply(
        _ edit: ReadOnlyAttributedEdit,
        to value: NSMutableAttributedString
    ) {
        let unannotated = NSAttributedString(string: "unannotated")
        switch edit {
        case .copyOnly:
            break
        case .prependUnannotatedText:
            value.insert(unannotated, at: 0)
        case .appendUnannotatedText:
            value.append(unannotated)
        case .replaceLeadingRange:
            value.replaceCharacters(
                in: NSRange(location: 0, length: min(3, value.length)),
                with: unannotated
            )
        case .deletePartialRange:
            value.deleteCharacters(
                in: NSRange(location: 0, length: min(3, value.length))
            )
        case .replaceEveryOriginalRange:
            value.replaceCharacters(
                in: NSRange(location: 0, length: value.length),
                with: unannotated
            )
        case .deleteEveryOriginalRangeAfterPrependingText:
            let originalLength = value.length
            value.insert(NSAttributedString(string: "X"), at: 0)
            value.deleteCharacters(
                in: NSRange(
                    location: 1,
                    length: originalLength
                )
            )
        case .stripAllAttributes:
            value.setAttributedString(NSAttributedString(string: value.string))
        case .emptyAllContent:
            value.deleteCharacters(in: NSRange(location: 0, length: value.length))
        }
    }

    private func expectedError(
        for edit: ReadOnlyAttributedEdit,
        fixture: ReadOnlyFixture
    ) -> RichTextDocumentCodecError {
        switch edit {
        case .replaceEveryOriginalRange,
             .deleteEveryOriginalRangeAfterPrependingText,
             .stripAllAttributes,
             .emptyAllContent:
            .validationFailure
        case .copyOnly,
             .prependUnannotatedText,
             .appendUnannotatedText,
             .replaceLeadingRange,
             .deletePartialRange:
            .readOnly(fixture.reason)
        }
    }
}
