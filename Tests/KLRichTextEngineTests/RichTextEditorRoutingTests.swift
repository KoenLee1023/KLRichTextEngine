import Foundation
import Testing
@testable import KLRichTextEngine

@Suite
struct RichTextEditorRoutingTests {
    @Test(arguments: [
        (17, RichTextEditorResolvedBackend.textKitCompatibility),
        (25, RichTextEditorResolvedBackend.textKitCompatibility),
        (26, RichTextEditorResolvedBackend.swiftUI),
    ])
    func `automatic routing changes at iOS 26`(
        majorVersion: Int,
        expected: RichTextEditorResolvedBackend
    ) {
        let capability = TestVersionCapability(majorVersion: majorVersion)

        #expect(RichTextEditorRouting.automatic(capability: capability) == expected)
    }

    @Test
    func `read only access suppresses mutation toolbar`() {
        #expect(RichTextEditorCoordinatorState.shouldShowMutationToolbar(access: .editable))
        #expect(!RichTextEditorCoordinatorState.shouldShowMutationToolbar(
            access: .readOnly(.unknownSchema(99))
        ))
    }

    @Test
    func `same plain text with different formatting requires refresh`() {
        let current = NSAttributedString(string: "Same")
        let expected = NSMutableAttributedString(string: "Same")
        expected.addAttribute(
            .underlineStyle,
            value: 1,
            range: NSRange(location: 0, length: expected.length)
        )

        #expect(RichTextEditorCoordinatorState.shouldApplyExternalValue(
            current: current,
            expected: expected,
            hasMarkedText: false
        ))
        #expect(!RichTextEditorCoordinatorState.shouldApplyExternalValue(
            current: current,
            expected: expected,
            hasMarkedText: true
        ))
        #expect(!RichTextEditorCoordinatorState.shouldApplyExternalValue(
            current: expected,
            expected: expected,
            hasMarkedText: false
        ))
    }

    @Test
    func `focus requests are consumed once`() {
        var state = RichTextEditorCoordinatorState(initialFocusRequest: 4)

        let repeatedInitialRequest = state.consumeFocusRequest(4)
        let newRequest = state.consumeFocusRequest(5)
        let repeatedNewRequest = state.consumeFocusRequest(5)

        #expect(!repeatedInitialRequest)
        #expect(newRequest)
        #expect(!repeatedNewRequest)
    }

    @Test
    func `single Return insertion is identified at its UTF16 offset`() {
        let selection = RichTextEditorCoordinatorState.singleInsertedNewlineSelection(
            previous: "A😀B",
            updated: "A😀\nB"
        )

        #expect(selection == RichTextSelection(locationUTF16: 3, lengthUTF16: 0))
        #expect(RichTextEditorCoordinatorState.singleInsertedNewlineSelection(
            previous: "A",
            updated: "A\n\n"
        ) == nil)
    }

    @MainActor
    @Test
    func `TextKit actual Return input uses the shared checklist mutation`() throws {
        let checklistID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000701")
        )
        let document = RichTextDocument(blocks: [
            .checklistItem(
                RichTextChecklistItem(
                    id: checklistID,
                    isChecked: true,
                    content: RichTextContent(plainText: "Task")
                )
            ),
        ])
        let codec = RichTextDocumentCodec(
            validationPolicy: RichTextDocumentValidationPolicy(
                maximumBlockCount: 10,
                maximumTextUTF8Bytes: 1_000,
                maximumEmbeddedDataBytes: 1_000
            )
        )
        let engine = RichTextMutationEngine(documentCodec: codec)
        var value = try codec.attributedString(from: document)
        var mutatedDocument = document
        var selection = RichTextSelection(locationUTF16: 4, lengthUTF16: 0)

        let route = try RichTextEditorCoordinatorState.routeTextKitReplacement(
            "\n",
            replacing: NSRange(location: 4, length: 0),
            access: .editable,
            hasMarkedText: false,
            to: &value,
            document: &mutatedDocument,
            selection: &selection,
            mutationEngine: engine
        )

        #expect(route == .handled)
        #expect(mutatedDocument.blocks.count == 2)
        #expect(mutatedDocument.blocks[0].id == checklistID)
        guard case let .checklistItem(inserted) = mutatedDocument.blocks[1] else {
            Issue.record("Expected the shared checklist command to insert a checklist item")
            return
        }
        #expect(!inserted.isChecked)
        #expect(inserted.content.plainText.isEmpty)
        #expect(selection == RichTextSelection(locationUTF16: 5, lengthUTF16: 0))
    }

    @MainActor
    @Test
    func `TextKit replacement router classifies every delegate replacement`() throws {
        let checklistID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000702")
        )
        let original = RichTextDocument(blocks: [
            .checklistItem(
                RichTextChecklistItem(
                    id: checklistID,
                    isChecked: true,
                    content: RichTextContent(plainText: "Task")
                )
            ),
        ])
        let codec = RichTextDocumentCodec(
            validationPolicy: RichTextDocumentValidationPolicy(
                maximumBlockCount: 10,
                maximumTextUTF8Bytes: 1_000,
                maximumEmbeddedDataBytes: 1_000
            )
        )
        let engine = RichTextMutationEngine(documentCodec: codec)

        var newlineValue = try codec.attributedString(from: original)
        var newlineDocument = original
        var newlineSelection = RichTextSelection(locationUTF16: 0, lengthUTF16: 0)
        let newline = try RichTextEditorCoordinatorState.routeTextKitReplacement(
            "\n",
            replacing: NSRange(location: 4, length: 0),
            access: .editable,
            hasMarkedText: false,
            to: &newlineValue,
            document: &newlineDocument,
            selection: &newlineSelection,
            mutationEngine: engine
        )

        #expect(newline == .handled)
        #expect(newlineDocument.blocks.count == 2)
        #expect(newlineSelection == RichTextSelection(locationUTF16: 5, lengthUTF16: 0))

        for text in ["\\n", "x"] {
            var value = try codec.attributedString(from: original)
            var document = original
            var selection = RichTextSelection(locationUTF16: 1, lengthUTF16: 0)

            let route = try RichTextEditorCoordinatorState.routeTextKitReplacement(
                text,
                replacing: NSRange(location: 1, length: 0),
                access: .editable,
                hasMarkedText: false,
                to: &value,
                document: &document,
                selection: &selection,
                mutationEngine: engine
            )

            #expect(route == .passThrough)
            #expect(document == original)
            #expect(selection == RichTextSelection(locationUTF16: 1, lengthUTF16: 0))
        }

        var readOnlyValue = try codec.attributedString(from: original)
        var readOnlyDocument = original
        var readOnlySelection = RichTextSelection(locationUTF16: 0, lengthUTF16: 0)
        let readOnly = try RichTextEditorCoordinatorState.routeTextKitReplacement(
            "\n",
            replacing: NSRange(location: 4, length: 0),
            access: .readOnly(.invalidPayload),
            hasMarkedText: false,
            to: &readOnlyValue,
            document: &readOnlyDocument,
            selection: &readOnlySelection,
            mutationEngine: engine
        )

        #expect(readOnly == .reject)
        #expect(readOnlyDocument == original)

        var markedValue = try codec.attributedString(from: original)
        var markedDocument = original
        var markedSelection = RichTextSelection(locationUTF16: 0, lengthUTF16: 0)
        let marked = try RichTextEditorCoordinatorState.routeTextKitReplacement(
            "\n",
            replacing: NSRange(location: 4, length: 0),
            access: .editable,
            hasMarkedText: true,
            to: &markedValue,
            document: &markedDocument,
            selection: &markedSelection,
            mutationEngine: engine
        )

        #expect(marked == .passThrough)
        #expect(markedDocument == original)
        #expect(markedSelection == RichTextSelection(locationUTF16: 0, lengthUTF16: 0))
    }

    @MainActor
    @Test
    func `TextKit replacement router leaves state unchanged when mutation fails`() throws {
        let document = RichTextDocument(blocks: [
            .paragraph(
                RichTextParagraph(
                    id: UUID(),
                    content: RichTextContent(plainText: "Task")
                )
            ),
        ])
        let codec = RichTextDocumentCodec(
            validationPolicy: RichTextDocumentValidationPolicy(
                maximumBlockCount: 1,
                maximumTextUTF8Bytes: 1_000,
                maximumEmbeddedDataBytes: 1_000
            )
        )
        let engine = RichTextMutationEngine(documentCodec: codec)
        var value = try codec.attributedString(from: document)
        let originalValue = NSAttributedString(attributedString: value)
        var mutatedDocument = document
        var selection = RichTextSelection(locationUTF16: 1, lengthUTF16: 0)

        #expect(throws: RichTextDocumentCodecError.validationFailure) {
            try RichTextEditorCoordinatorState.routeTextKitReplacement(
                "\n",
                replacing: NSRange(location: 4, length: 0),
                access: .editable,
                hasMarkedText: false,
                to: &value,
                document: &mutatedDocument,
                selection: &selection,
                mutationEngine: engine
            )
        }

        #expect(value.isEqual(to: originalValue))
        #expect(mutatedDocument == document)
        #expect(selection == RichTextSelection(locationUTF16: 1, lengthUTF16: 0))
    }

    @Test
    func `self published document echo is consumed once`() {
        let published = RichTextDocument(blocks: [
            .paragraph(
                RichTextParagraph(
                    id: UUID(),
                    content: RichTextContent(plainText: "Composing")
                )
            ),
        ])
        var state = RichTextEditorCoordinatorState(initialFocusRequest: 0)

        state.recordPublishedDocument(published)
        let selfEcho = state.shouldRefreshForDocumentChange(published)
        let laterExternalChange = state.shouldRefreshForDocumentChange(published)

        #expect(!selfEcho)
        #expect(laterExternalChange)
    }
}

private struct TestVersionCapability: RichTextEditorVersionCapability {
    let majorVersion: Int

    var supportsSwiftUIRichTextEditor: Bool {
        majorVersion >= 26
    }
}
