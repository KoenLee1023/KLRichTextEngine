#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import KLRichTextEngine

@MainActor
@Suite
struct RichTextDynamicTypeTests {
    private let codec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: 20,
            maximumTextUTF8Bytes: 100_000,
            maximumEmbeddedDataBytes: 1_000_000
        )
    )
    private let normalizer = RichTextFontNormalizer()
    private let policy = RichTextDynamicTypePolicy()

    @Test
    func `external 34 point font normalizes to dynamic body without redundant RTF`() throws {
        let imported = NSMutableAttributedString(string: "Imported")
        imported.addAttribute(
            .font,
            value: NSFont(name: "Times New Roman", size: 34) ?? NSFont.systemFont(ofSize: 34),
            range: imported.fullRange
        )

        let document = try parseNewEditable(imported)
        let content = try #require(document.blocks.first?.content)

        #expect(content.fontStorageMode == .dynamicBodyV1)
        #expect(content.fontIntentRuns.isEmpty)
        #expect(content.rtfData == nil)

        let rendered = try codec.attributedString(from: document)
        let resolved = normalizer.resolvingFonts(
            in: rendered,
            contentSizeCategory: .large
        )
        let font = try font(in: resolved)
        #expect(abs(font.pointSize - policy.pointSize(
            for: .dynamicBody,
            contentSizeCategory: .large
        )) < 0.01)
        #expect(font.fontDescriptor.symbolicTraits.subtracting(.classMask).isEmpty)
    }

    @Test
    func `explicit fixed 29 point intent remains fixed and preserves RTF`() throws {
        let source = NSAttributedString(
            string: "Fixed",
            attributes: [.font: NSFont.systemFont(ofSize: 42)]
        )
        let marked = normalizer.applying(
            .fixedPointSize(29),
            to: source.fullRange,
            in: source,
            contentSizeCategory: .large
        )

        let document = try parseNewEditable(marked)
        let content = try #require(document.blocks.first?.content)
        #expect(content.rtfData != nil)
        #expect(content.fontIntentRuns.map(\.intent) == [.fixedPointSize(29)])

        let data = try codec.encodeJSON(document, version: .v1)
        let loaded = codec.loadJSON(data, fallbackPlainText: "fallback")
        #expect(loaded.access == .editable)
        let rendered = try codec.attributedString(from: loaded.document)
        let resolved = normalizer.resolvingFonts(
            in: rendered,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        #expect(abs(try font(in: resolved).pointSize - 29) < 0.01)
    }

    @Test(arguments: [
        RichTextFontIntent.dynamicBody,
        .dynamicTextStyle(.title),
        .dynamicTextStyle(.heading),
    ])
    func `semantic intents scale from large to accessibility sizes`(
        intent: RichTextFontIntent
    ) {
        let large = policy.pointSize(for: intent, contentSizeCategory: .large)
        let accessibility = policy.pointSize(
            for: intent,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )

        #expect(accessibility > large)
    }

    @Test
    func `bold and italic symbolic traits survive body normalization`() throws {
        let manager = NSFontManager.shared
        let bold = manager.convert(
            NSFont.systemFont(ofSize: 34),
            toHaveTrait: .boldFontMask
        )
        let boldItalic = manager.convert(bold, toHaveTrait: .italicFontMask)
        let imported = NSAttributedString(
            string: "Traits",
            attributes: [.font: boldItalic]
        )

        let document = try parseNewEditable(imported)
        let content = try #require(document.blocks.first?.content)
        #expect(content.rtfData != nil)

        let rendered = try codec.attributedString(from: document)
        let resolved = normalizer.resolvingFonts(
            in: rendered,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        let traits = manager.traits(of: try font(in: resolved))
        #expect(traits.contains(.boldFontMask))
        #expect(traits.contains(.italicFontMask))
    }

    @Test
    func `semantic and fixed intents persist only in v1 JSON`() throws {
        let source = NSAttributedString(
            string: "Title fixed",
            attributes: [.font: NSFont.systemFont(ofSize: 17)]
        )
        let titleRange = NSRange(location: 0, length: 5)
        let fixedRange = NSRange(location: 6, length: 5)
        let title = normalizer.applying(
            .dynamicTextStyle(.title),
            to: titleRange,
            in: source,
            contentSizeCategory: .large
        )
        let marked = normalizer.applying(
            .fixedPointSize(29),
            to: fixedRange,
            in: title,
            contentSizeCategory: .large
        )
        let document = try parseNewEditable(marked)

        let v0 = try codec.encodeJSON(document, version: .v0)
        let v1 = try codec.encodeJSON(document, version: .v1)
        #expect(String(decoding: v0, as: UTF8.self).contains("fontIntentRuns") == false)
        #expect(String(decoding: v1, as: UTF8.self).contains("fontIntentRuns"))

        let directData = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(RichTextDocument.self, from: directData) == document)

        let loaded = codec.loadJSON(v1, fallbackPlainText: "fallback")
        let runs = try #require(loaded.document.blocks.first?.content.fontIntentRuns)
        #expect(runs.map(\.intent) == [
            .dynamicTextStyle(.title),
            .fixedPointSize(29),
        ])
    }

    @Test
    func `runtime font intent never serializes into RTF`() throws {
        let source = NSAttributedString(
            string: "Fixed",
            attributes: [.font: NSFont.systemFont(ofSize: 17)]
        )
        let marked = normalizer.applying(
            .fixedPointSize(29),
            to: source.fullRange,
            in: source,
            contentSizeCategory: .large
        )
        let document = try parseNewEditable(marked)
        let rtfData = try #require(document.blocks.first?.content.rtfData)
        let decoded = try NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )

        #expect(decoded.attribute(
            RichTextRuntimeAttributes.fontIntent,
            at: 0,
            effectiveRange: nil
        ) == nil)
    }

    @Test(arguments: [
        NSRange(location: -1, length: 1),
        NSRange(location: 0, length: -1),
        NSRange(location: 0, length: 0),
        NSRange(location: 1, length: 1),
        NSRange(location: 2, length: 1),
        NSRange(location: 1, length: .max),
        NSRange(location: .max, length: .max),
    ])
    func `invalid public application ranges return the original value`(
        range: NSRange
    ) {
        let source = NSAttributedString(
            string: "😀",
            attributes: [.font: NSFont.systemFont(ofSize: 17)]
        )

        let result = normalizer.applying(
            .fixedPointSize(29),
            to: range,
            in: source,
            contentSizeCategory: .large
        )

        #expect(result === source)
        #expect(result == source)
    }

    @Test
    func `public rendering and serialization reject every malformed font run set`() throws {
        let intent = RichTextFontIntent.dynamicTextStyle(.title)
        let malformedContents = [
            RichTextContent(
                plainText: "ab",
                fontIntentRuns: [.init(utf16Location: -1, utf16Length: 1, intent: intent)]
            ),
            RichTextContent(
                plainText: "ab",
                fontIntentRuns: [.init(utf16Location: 0, utf16Length: -1, intent: intent)]
            ),
            RichTextContent(
                plainText: "ab",
                fontIntentRuns: [.init(utf16Location: 0, utf16Length: 0, intent: intent)]
            ),
            RichTextContent(
                plainText: "ab",
                fontIntentRuns: [.init(utf16Location: 1, utf16Length: .max, intent: intent)]
            ),
            RichTextContent(
                plainText: "ab",
                fontIntentRuns: [.init(utf16Location: .max, utf16Length: .max, intent: intent)]
            ),
            RichTextContent(
                plainText: "ab",
                fontIntentRuns: [.init(utf16Location: 2, utf16Length: 1, intent: intent)]
            ),
            RichTextContent(
                plainText: "ab",
                fontIntentRuns: [
                    .init(utf16Location: 0, utf16Length: 1, intent: intent),
                    .init(utf16Location: 0, utf16Length: 1, intent: intent),
                ]
            ),
            RichTextContent(
                plainText: "abc",
                fontIntentRuns: [
                    .init(utf16Location: 0, utf16Length: 2, intent: intent),
                    .init(utf16Location: 1, utf16Length: 2, intent: intent),
                ]
            ),
            RichTextContent(
                plainText: "😀",
                fontIntentRuns: [.init(utf16Location: 1, utf16Length: 1, intent: intent)]
            ),
        ]

        for content in malformedContents {
            let document = RichTextDocument(
                blocks: [.paragraph(RichTextParagraph(id: UUID(), content: content))]
            )
            #expect(throws: RichTextDocumentCodecError.validationFailure) {
                try codec.attributedString(from: document)
            }
            #expect(throws: RichTextDocumentCodecError.validationFailure) {
                try codec.encodeJSON(document, version: .v1)
            }
            #expect(throws: RichTextDocumentCodecError.validationFailure) {
                try codec.encodeJSON(document, version: .v0)
            }
            #expect(throws: EncodingError.self) {
                try JSONEncoder().encode(content)
            }
        }
    }

    @Test
    func `invalid v1 font intent ranges load read only`() throws {
        let content = RichTextContent(
            plainText: "Short",
            fontStorageMode: .dynamicBodyV1,
            fontIntentRuns: [
                RichTextFontIntent.Run(
                    utf16Location: 0,
                    utf16Length: 5,
                    intent: .dynamicTextStyle(.title)
                ),
            ]
        )
        let document = RichTextDocument(
            blocks: [.paragraph(RichTextParagraph(id: UUID(), content: content))]
        )
        let encoder = JSONEncoder()
        encoder.userInfo[.richTextSchemaVersion] = 1
        let encoded = try encoder.encode(document)
        var root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var blocks = try #require(root["blocks"] as? [[String: Any]])
        var paragraph = try #require(blocks[0]["paragraph"] as? [String: Any])
        var text = try #require(paragraph["text"] as? [String: Any])
        var runs = try #require(text["fontIntentRuns"] as? [[String: Any]])
        runs[0]["utf16Length"] = 500
        text["fontIntentRuns"] = runs
        paragraph["text"] = text
        blocks[0]["paragraph"] = paragraph
        root["blocks"] = blocks
        root["schemaVersion"] = 1
        let malformed = try JSONSerialization.data(withJSONObject: root)

        let result = codec.loadJSON(malformed, fallbackPlainText: "fallback")
        #expect(result.access == .readOnly(.validationFailure))
    }

    @Test
    func `twelve normalize encode decode cycles neither double scale nor drift`() throws {
        let source = NSAttributedString(
            string: "Stable title",
            attributes: [.font: NSFont.systemFont(ofSize: 61)]
        )
        let marked = normalizer.applying(
            .dynamicTextStyle(.title),
            to: source.fullRange,
            in: source,
            contentSizeCategory: .large
        )
        var document = try parseNewEditable(marked)
        let expected = policy.pointSize(
            for: .dynamicTextStyle(.title),
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )

        for _ in 0..<12 {
            let encoded = try codec.encodeJSON(document, version: .v1)
            let loaded = codec.loadJSON(encoded, fallbackPlainText: "fallback")
            #expect(loaded.access == .editable)

            let rendered = try codec.attributedString(from: loaded.document)
            let resolved = normalizer.resolvingFonts(
                in: rendered,
                contentSizeCategory: .accessibilityExtraExtraExtraLarge
            )
            #expect(abs(try font(in: resolved).pointSize - expected) < 0.01)
            document = try codec.document(from: resolved, reconciling: loaded.document)
        }

        let content = try #require(document.blocks.first?.content)
        #expect(content.fontIntentRuns.map(\.intent) == [.dynamicTextStyle(.title)])
        let canonical = try codec.attributedString(from: document)
        #expect(abs(try font(in: canonical).pointSize - policy.pointSize(
            for: .dynamicTextStyle(.title),
            contentSizeCategory: .large
        )) < 0.01)
    }

    @Test
    func `canonical RTF normalization preserves authoritative coordinates for twelve cycles`() throws {
        let expectedUTF16: [UInt16] = [
            0x0041,
            0xD83D, 0xDE00,
            0x0065, 0x0301,
            0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDCBB,
            0x005A,
        ]
        let expectedRuns = [
            RichTextFontIntent.Run(
                utf16Location: 1,
                utf16Length: 2,
                intent: .dynamicTextStyle(.title)
            ),
            RichTextFontIntent.Run(
                utf16Location: 5,
                utf16Length: 5,
                intent: .fixedPointSize(29)
            ),
        ]
        let source = NSMutableAttributedString(string: "A😀e\u{301}👩‍💻Z")
        source.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 3, length: 7)
        )
        source.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 3, length: 2)
        )
        let titled = normalizer.applying(
            .dynamicTextStyle(.title),
            to: NSRange(location: 1, length: 2),
            in: source,
            contentSizeCategory: .large
        )
        let marked = normalizer.applying(
            .fixedPointSize(29),
            to: NSRange(location: 5, length: 5),
            in: titled,
            contentSizeCategory: .large
        )
        var document = try parseNewEditable(marked)
        let initialContent = try #require(document.blocks.first?.content)
        let initialRTF = try #require(initialContent.rtfData)
        let independentlyDecoded = try NSAttributedString(
            data: initialRTF,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        #expect(independentlyDecoded.string == source.string)
        #expect(Array(independentlyDecoded.string.utf16) != expectedUTF16)

        let expectedTitleSize = policy.pointSize(
            for: .dynamicTextStyle(.title),
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        for _ in 0..<12 {
            let encoded = try codec.encodeJSON(document, version: .v1)
            let loaded = codec.loadJSON(encoded, fallbackPlainText: "fallback")
            #expect(loaded.access == .editable)

            let rendered = try codec.attributedString(from: loaded.document)
            try #require(Array(rendered.string.utf16) == expectedUTF16)
            #expect(
                rendered.attribute(.underlineStyle, at: 3, effectiveRange: nil) as? Int
                    == NSUnderlineStyle.single.rawValue
            )
            #expect(
                rendered.attribute(.underlineStyle, at: 5, effectiveRange: nil) as? Int
                    == NSUnderlineStyle.single.rawValue
            )
            #expect(
                rendered.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int
                    == NSUnderlineStyle.single.rawValue
            )

            let resolved = normalizer.resolvingFonts(
                in: rendered,
                contentSizeCategory: .accessibilityExtraExtraExtraLarge
            )
            #expect(abs(try font(in: resolved, at: 1).pointSize - expectedTitleSize) < 0.01)
            #expect(abs(try font(in: resolved, at: 5).pointSize - 29) < 0.01)

            document = try codec.document(from: resolved, reconciling: loaded.document)
            let content = try #require(document.blocks.first?.content)
            #expect(Array(content.plainText.utf16) == expectedUTF16)
            #expect(content.fontIntentRuns == expectedRuns)
            #expect(content.rtfData != nil)
        }
    }

    @Test
    func `multiple canonical differences preserve marks inside styled runs`() throws {
        let expectedUTF16: [UInt16] = [
            0x0078, 0x0041, 0x030A, 0x0079, 0x004F, 0x0308, 0x007A,
        ]
        let expectedRuns = [
            RichTextFontIntent.Run(
                utf16Location: 1,
                utf16Length: 2,
                intent: .dynamicTextStyle(.title)
            ),
            RichTextFontIntent.Run(
                utf16Location: 4,
                utf16Length: 2,
                intent: .fixedPointSize(29)
            ),
        ]
        let source = NSMutableAttributedString(string: "xA\u{30A}yO\u{308}z")
        source.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 1, length: 5)
        )
        source.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 4, length: 2)
        )
        let titled = normalizer.applying(
            .dynamicTextStyle(.title),
            to: NSRange(location: 1, length: 2),
            in: source,
            contentSizeCategory: .large
        )
        let marked = normalizer.applying(
            .fixedPointSize(29),
            to: NSRange(location: 4, length: 2),
            in: titled,
            contentSizeCategory: .large
        )
        let document = try parseNewEditable(marked)
        let content = try #require(document.blocks.first?.content)
        let decoded = try NSAttributedString(
            data: #require(content.rtfData),
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        #expect(decoded.string == source.string)
        #expect(Array(decoded.string.utf16) != expectedUTF16)

        let rendered = try codec.attributedString(from: document)
        try #require(Array(rendered.string.utf16) == expectedUTF16)
        #expect(
            rendered.attribute(.underlineStyle, at: 2, effectiveRange: nil) as? Int
                == NSUnderlineStyle.single.rawValue
        )
        #expect(
            rendered.attribute(.underlineStyle, at: 5, effectiveRange: nil) as? Int
                == NSUnderlineStyle.single.rawValue
        )
        #expect(
            rendered.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) as? Int
                == NSUnderlineStyle.single.rawValue
        )
        let resolved = normalizer.resolvingFonts(
            in: rendered,
            contentSizeCategory: .large
        )
        #expect(abs(try font(in: resolved, at: 1).pointSize - policy.pointSize(
            for: .dynamicTextStyle(.title),
            contentSizeCategory: .large
        )) < 0.01)
        #expect(abs(try font(in: resolved, at: 4).pointSize - 29) < 0.01)

        let reparsed = try codec.document(from: resolved, reconciling: document)
        #expect(reparsed.blocks.first?.content.fontIntentRuns == expectedRuns)
        #expect(Array(try #require(reparsed.blocks.first?.content.plainText).utf16) == expectedUTF16)
    }

    @Test
    func `unmappable RTF falls back without losing persisted font intents`() throws {
        let expectedUTF16: [UInt16] = [
            0x0041, 0xD83D, 0xDE00, 0x0065, 0x0301, 0x005A,
        ]
        let unrelated = NSAttributedString(
            string: "Different",
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        let expectedRuns = [
            RichTextFontIntent.Run(
                utf16Location: 1,
                utf16Length: 2,
                intent: .dynamicTextStyle(.title)
            ),
            RichTextFontIntent.Run(
                utf16Location: 5,
                utf16Length: 1,
                intent: .fixedPointSize(29)
            ),
        ]
        let content = RichTextContent(
            plainText: "A😀e\u{301}Z",
            rtfData: try unrelated.data(
                from: unrelated.fullRange,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ),
            fontStorageMode: .dynamicBodyV1,
            fontIntentRuns: expectedRuns
        )
        let document = RichTextDocument(
            blocks: [.paragraph(RichTextParagraph(id: UUID(), content: content))]
        )

        let rendered = try codec.attributedString(from: document)
        try #require(Array(rendered.string.utf16) == expectedUTF16)
        #expect(rendered.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
        let resolved = normalizer.resolvingFonts(
            in: rendered,
            contentSizeCategory: .large
        )
        #expect(abs(try font(in: resolved, at: 1).pointSize - policy.pointSize(
            for: .dynamicTextStyle(.title),
            contentSizeCategory: .large
        )) < 0.01)
        #expect(abs(try font(in: resolved, at: 5).pointSize - 29) < 0.01)

        let reparsed = try codec.document(from: resolved, reconciling: document)
        #expect(reparsed.blocks.first?.content.fontIntentRuns == expectedRuns)
        #expect(Array(try #require(reparsed.blocks.first?.content.plainText).utf16) == expectedUTF16)
    }

    @Test
    func `v0 dynamic body storage remains decodable and scalable`() throws {
        let canonical = NSAttributedString(
            string: "Legacy dynamic",
            attributes: [.font: NSFont.systemFont(ofSize: 17)]
        )
        let content = RichTextContent(
            plainText: canonical.string,
            rtfData: try canonical.data(
                from: canonical.fullRange,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ),
            fontStorageMode: .dynamicBodyV1
        )
        let document = RichTextDocument(
            blocks: [.paragraph(RichTextParagraph(id: UUID(), content: content))]
        )

        let data = try codec.encodeJSON(document, version: .v0)
        let loaded = codec.loadJSON(data, fallbackPlainText: "fallback")
        #expect(loaded.access == .editable)
        #expect(loaded.document.blocks.first?.content.fontStorageMode == .dynamicBodyV1)

        let rendered = try codec.attributedString(from: loaded.document)
        let accessibility = normalizer.resolvingFonts(
            in: rendered,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        #expect(abs(try font(in: accessibility).pointSize - policy.pointSize(
            for: .dynamicBody,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )) < 0.01)
    }

    private func parseNewEditable(_ value: NSAttributedString) throws -> RichTextDocument {
        let editable = try codec.editableAttributedString(from: value)
        return try codec.document(from: editable, reconciling: nil)
    }

    private func font(in value: NSAttributedString) throws -> NSFont {
        try font(in: value, at: 0)
    }

    private func font(in value: NSAttributedString, at location: Int) throws -> NSFont {
        try #require(value.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }
}

private extension NSAttributedString {
    var fullRange: NSRange {
        NSRange(location: 0, length: length)
    }
}
#endif
