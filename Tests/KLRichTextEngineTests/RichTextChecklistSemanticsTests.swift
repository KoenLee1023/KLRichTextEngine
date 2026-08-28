import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Testing
@testable import KLRichTextEngine
#if canImport(AppKit)
import AppKit
#endif

@MainActor
@Suite
struct RichTextChecklistSemanticsTests {
    private let checklistCodec = RichTextChecklistCodec()
    private let documentCodec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: .max,
            maximumTextUTF8Bytes: .max,
            maximumEmbeddedDataBytes: .max
        )
    )
    private let mutation = RichTextChecklistMutation()

    @Test
    func `completion decoration is removed when a parsed checklist becomes unchecked`() throws {
        let document = try checkedDocument()
        let rendered = try checklistCodec.render(document)
        let checkedMarker = rendered.attribute(
            RichTextRuntimeAttributes.checklistCompletionDecoration,
            at: 0,
            effectiveRange: nil
        ) as? Bool
        #expect(checkedMarker == true)

        let parsed = try checklistCodec.parse(rendered, reconciling: document)
        let unchecked = try mutation.togglingItem(id: document.blocks[0].id, in: parsed)
        let rerendered = try checklistCodec.render(unchecked)

        #expect(
            rerendered.attribute(
                RichTextRuntimeAttributes.checklistCompletionDecoration,
                at: 0,
                effectiveRange: nil
            ) == nil
        )
    }

    @Test
    func `authored formatting payload survives checklist completion changes`() throws {
        let document = try checkedDocument()
        let itemID = document.blocks[0].id

        let unchecked = try mutation.togglingItem(id: itemID, in: document)
        let checkedAgain = try mutation.togglingItem(id: itemID, in: unchecked)
        let parsed = try checklistCodec.parse(
            checklistCodec.render(checkedAgain),
            reconciling: checkedAgain
        )

        guard case let .checklistItem(item) = parsed.blocks[0] else {
            Issue.record("Expected a checklist item")
            return
        }
        let authored = RichTextRTFCodec().attributedString(from: item.content)
        #expect(authored.string == "Synthetic task")
        #expect(
            authored.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int
                == NSUnderlineStyle.single.rawValue
        )
        #expect(
            authored.attribute(
                .strikethroughStyle,
                at: authored.length - 1,
                effectiveRange: nil
            ) == nil
        )
        #expect(item.isChecked)
    }

    @Test
    func `return after a checked item creates a new unchecked item`() throws {
        let document = try checkedDocument()
        let existingID = document.blocks[0].id
        let result = try mutation.pressingReturn(
            inItemWithID: existingID,
            atUTF16Offset: document.blocks[0].plainText.utf16.count,
            in: document
        )

        #expect(result.blocks.count == 2)
        #expect(result.blocks[0].id == existingID)
        #expect(result.blocks[1].id != existingID)
        guard case let .checklistItem(newItem) = result.blocks[1] else {
            Issue.record("Expected a new checklist item")
            return
        }
        #expect(!newItem.isChecked)
        #expect(newItem.content.plainText.isEmpty)
    }

    @Test
    func `return rejects an overflowing font run before splitting two characters`() throws {
        let itemID = try #require(
            UUID(uuidString: "50000000-0000-0000-0000-000000000010")
        )
        let content = RichTextContent(
            plainText: "AB",
            fallbackMarkdown: "AB",
            fontStorageMode: .dynamicBodyV1,
            fontIntentRuns: [
                RichTextFontIntent.Run(
                    utf16Location: 1,
                    utf16Length: .max,
                    intent: .dynamicTextStyle(.heading)
                ),
            ]
        )
        let document = RichTextDocument(
            blocks: [
                .checklistItem(
                    RichTextChecklistItem(
                        id: itemID,
                        isChecked: false,
                        content: content
                    )
                ),
            ]
        )

        #expect(throws: RichTextChecklistMutationError.readOnly(.invalidPayload)) {
            try mutation.pressingReturn(
                inItemWithID: itemID,
                atUTF16Offset: 1,
                in: document
            )
        }
        #expect(throws: RichTextChecklistMutationError.readOnly(.invalidPayload)) {
            try mutation.togglingItem(id: itemID, in: document)
        }
        #expect(document.blocks[0].content == content)
    }

#if canImport(AppKit)
    @Test
    func `return inside an item splits authored RTF across both resulting items`() throws {
        let itemID = try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000008"))
        let authored = NSMutableAttributedString(string: "BoldUnderlined")
        authored.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 15),
            range: NSRange(location: 0, length: 4)
        )
        authored.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 4, length: 10)
        )
        let document = RichTextDocument(
            blocks: [
                .checklistItem(
                    RichTextChecklistItem(
                        id: itemID,
                        isChecked: true,
                        content: RichTextContent(
                            plainText: authored.string,
                            rtfData: try rtfData(from: authored),
                            fallbackMarkdown: "BoldUnderlined",
                            fontStorageMode: .dynamicBodyV1
                        )
                    )
                ),
            ]
        )

        let result = try mutation.pressingReturn(
            inItemWithID: itemID,
            atUTF16Offset: 4,
            in: document
        )

        guard case let .checklistItem(first) = result.blocks[0],
              case let .checklistItem(second) = result.blocks[1]
        else {
            Issue.record("Expected two checklist items")
            return
        }
        let firstAttributed = try attributedString(fromRTF: #require(first.content.rtfData))
        let secondAttributed = try attributedString(fromRTF: #require(second.content.rtfData))
        let firstFont = try #require(firstAttributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(first.content.plainText == "Bold")
        #expect(second.content.plainText == "Underlined")
        #expect(first.content.fallbackMarkdown == "Bold")
        #expect(second.content.fallbackMarkdown == "Underlined")
        #expect(first.content.fontStorageMode == .dynamicBodyV1)
        #expect(second.content.fontStorageMode == .dynamicBodyV1)
        #expect(NSFontManager.shared.traits(of: firstFont).contains(.boldFontMask))
        #expect(
            secondAttributed.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int
                == NSUnderlineStyle.single.rawValue
        )
        #expect(first.id == itemID)
        #expect(first.isChecked)
        #expect(!second.isChecked)
    }
#endif

    @Test
    func `return on an empty checklist item exits checklist mode without changing its ID`() throws {
        let itemID = try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000002"))
        let document = RichTextDocument(
            blocks: [
                .checklistItem(
                    RichTextChecklistItem(
                        id: itemID,
                        isChecked: false,
                        content: RichTextContent(plainText: "")
                    )
                ),
            ]
        )

        let result = try mutation.pressingReturn(
            inItemWithID: itemID,
            atUTF16Offset: 0,
            in: document
        )

        #expect(result.blocks.count == 1)
        #expect(result.blocks[0].id == itemID)
        guard case .paragraph = result.blocks[0] else {
            Issue.record("Expected checklist mode to end")
            return
        }
    }

    @Test
    func `empty checklist item preserves semantics through render and parse`() throws {
        let itemID = try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000005"))
        let document = RichTextDocument(
            blocks: [
                .checklistItem(
                    RichTextChecklistItem(
                        id: itemID,
                        isChecked: true,
                        content: RichTextContent(
                            plainText: "",
                            rtfData: Data(#"{\rtf1\ansi }"#.utf8)
                        )
                    )
                ),
            ]
        )

        let result = try checklistCodec.parse(
            checklistCodec.render(document),
            reconciling: document
        )

        #expect(result == document)
    }

    @Test
    func `final empty checklist item round trips without previous state`() throws {
        let firstID = try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000006"))
        let emptyID = try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000007"))
        let document = RichTextDocument(blocks: [
            .paragraph(
                RichTextParagraph(
                    id: firstID,
                    content: RichTextContent(plainText: "Before")
                )
            ),
            .checklistItem(
                RichTextChecklistItem(
                    id: emptyID,
                    isChecked: true,
                    content: RichTextContent(plainText: "")
                )
            ),
        ])

        let rendered = try checklistCodec.render(document)
        let copiedByCaller = NSAttributedString(attributedString: rendered)
        let result = try checklistCodec.parse(copiedByCaller, reconciling: nil)

        #expect(result == document)
    }

    @Test
    func `first and only empty checklist survives a caller copy without visible content`() throws {
        let itemID = try #require(
            UUID(uuidString: "50000000-0000-0000-0000-000000000009")
        )
        let document = RichTextDocument(
            blocks: [
                .checklistItem(
                    RichTextChecklistItem(
                        id: itemID,
                        isChecked: true,
                        content: RichTextContent(plainText: "")
                    )
                ),
            ]
        )

        let rendered = try checklistCodec.render(document)
        #expect(!rendered.string.isEmpty)
        #expect(
            rendered.string.unicodeScalars.allSatisfy {
                $0.properties.generalCategory == .format
            }
        )
        let callerCopy = NSAttributedString(attributedString: rendered)

        let result = try checklistCodec.parse(callerCopy, reconciling: nil)

        #expect(result == document)
        #expect(result.plainText.isEmpty)
    }

    @Test
    func `trailing empty paragraphs survive checklist render and parse`() throws {
        let task = try checkedDocument().blocks[0]
        let firstEmptyID = try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000003"))
        let secondEmptyID = try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000004"))
        let document = RichTextDocument(blocks: [
            task,
            .paragraph(RichTextParagraph(id: firstEmptyID, content: RichTextContent(plainText: ""))),
            .paragraph(RichTextParagraph(id: secondEmptyID, content: RichTextContent(plainText: ""))),
        ])

        let result = try checklistCodec.parse(
            checklistCodec.render(document),
            reconciling: document
        )

        #expect(result.blocks.map(\.id) == document.blocks.map(\.id))
        #expect(result.blocks.map(\.plainText) == ["Synthetic task", "", ""])
    }

    @Test
    func `CRLF boundaries create blocks without retaining carriage returns`() throws {
        let value = NSAttributedString(string: "First\r\nSecond\r\n")
        let editableValue = try documentCodec.editableAttributedString(from: value)

        let result = try checklistCodec.parse(editableValue, reconciling: nil)

        #expect(result.blocks.map(\.plainText) == ["First", "Second", ""])
        #expect(result.blocks.allSatisfy { block in
            guard case .paragraph = block else { return false }
            return true
        })
    }

    private func checkedDocument() throws -> RichTextDocument {
        let itemID = try #require(UUID(uuidString: "50000000-0000-0000-0000-000000000001"))
        return RichTextDocument(
            blocks: [
                .checklistItem(
                    RichTextChecklistItem(
                        id: itemID,
                        isChecked: true,
                        content: RichTextContent(
                            plainText: "Synthetic task",
                            rtfData: checkedRTFData,
                            fallbackMarkdown: "~~Synthetic~~ task"
                        )
                    )
                ),
            ]
        )
    }

    private var checkedRTFData: Data {
        Data(
            #"{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}\f0\fs24 \strike Synthetic\strike0  task}"#.utf8
        )
    }

#if canImport(AppKit)
    private func rtfData(from value: NSAttributedString) throws -> Data {
        try value.data(
            from: NSRange(location: 0, length: value.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private func attributedString(fromRTF data: Data) throws -> NSAttributedString {
        try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }
#endif
}
