#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import KLRichTextEngine

@MainActor
@Suite
struct RichTextRTFRoundTripTests {
    private let documentCodec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: 10,
            maximumTextUTF8Bytes: 10_000,
            maximumEmbeddedDataBytes: 100_000
        )
    )
    private let checklistCodec = RichTextChecklistCodec()

    @Test
    func `RTF content renders authored bold italic underline and strikethrough`() throws {
        let authored = NSMutableAttributedString(string: "Bold italic under strike")
        authored.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 17),
            range: NSRange(location: 0, length: 4)
        )
        authored.addAttribute(
            .font,
            value: NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: 17),
                toHaveTrait: .italicFontMask
            ),
            range: NSRange(location: 5, length: 6)
        )
        authored.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 12, length: 5)
        )
        authored.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 18, length: 6)
        )
        let document = RichTextDocument(
            blocks: [
                .paragraph(
                    RichTextParagraph(
                        id: UUID(),
                        content: RichTextContent(
                            plainText: authored.string,
                            rtfData: try rtfData(from: authored)
                        )
                    )
                ),
            ]
        )

        let rendered = try documentCodec.attributedString(from: document)

        let boldFont = try #require(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let italicFont = try #require(rendered.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
        #expect(NSFontManager.shared.traits(of: italicFont).contains(.italicFontMask))
        #expect((rendered.attribute(.underlineStyle, at: 12, effectiveRange: nil) as? Int) == 1)
        #expect((rendered.attribute(.strikethroughStyle, at: 18, effectiveRange: nil) as? Int) == 1)
    }

    @Test
    func `attributed formatting becomes authored RTF and renders back`() throws {
        let value = NSMutableAttributedString(string: "Plain styled")
        value.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 19),
            range: NSRange(location: 6, length: 6)
        )
        value.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 6, length: 6)
        )

        let editableValue = try documentCodec.editableAttributedString(from: value)
        let document = try documentCodec.document(from: editableValue, reconciling: nil)
        let content = try #require(document.blocks.first?.content)
        let storedRTF = try #require(content.rtfData)
        let independentlyDecoded = try attributedString(fromRTF: storedRTF)
        let storedFont = try #require(
            independentlyDecoded.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        )
        #expect(NSFontManager.shared.traits(of: storedFont).contains(.boldFontMask))
        #expect((independentlyDecoded.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int) == 1)
        for runtimeKey in RichTextRuntimeAttributes.all {
            #expect(
                independentlyDecoded.attribute(runtimeKey, at: 0, effectiveRange: nil) == nil
            )
        }

        let rendered = try documentCodec.attributedString(from: document)
        let renderedFont = try #require(rendered.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: renderedFont).contains(.boldFontMask))
        #expect((rendered.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int) == 1)
    }

    @Test
    func `checklist completion does not persist as authored strikethrough`() throws {
        let authored = NSMutableAttributedString(string: "Authored plain")
        authored.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 8)
        )
        let document = RichTextDocument(
            blocks: [
                .checklistItem(
                    RichTextChecklistItem(
                        id: UUID(),
                        isChecked: true,
                        content: RichTextContent(
                            plainText: authored.string,
                            rtfData: try rtfData(from: authored)
                        )
                    )
                ),
            ]
        )

        let rendered = try checklistCodec.render(document)
        #expect((rendered.attribute(.strikethroughStyle, at: 10, effectiveRange: nil) as? Int) == 1)
        let parsed = try checklistCodec.parse(rendered, reconciling: nil)
        let item = try checklistItem(in: parsed)
        let stored = try attributedString(fromRTF: #require(item.content.rtfData))

        #expect((stored.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) == 1)
        #expect(stored.attribute(.strikethroughStyle, at: 10, effectiveRange: nil) == nil)
    }

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

    private func checklistItem(in document: RichTextDocument) throws -> RichTextChecklistItem {
        let block = try #require(document.blocks.first)
        if case let .checklistItem(item) = block {
            return item
        }
        Issue.record("Expected checklist item")
        throw RichTextRTFTestError.expectedChecklistItem
    }
}

private enum RichTextRTFTestError: Error {
    case expectedChecklistItem
}
#endif
