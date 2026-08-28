#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import KLRichTextEngine

@MainActor
@Suite
struct RichTextUnicodeBoundaryTests {
    private let codec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: 20,
            maximumTextUTF8Bytes: 100_000,
            maximumEmbeddedDataBytes: 1_000_000
        )
    )
    private let normalizer = RichTextFontNormalizer()

    @Test
    func `UTF-16 validation accepts scalar boundaries inside graphemes`() {
        let text = "A😀e\u{301}👩‍💻Z"
        let validRanges = [
            NSRange(location: 3, length: 1),
            NSRange(location: 4, length: 1),
            NSRange(location: 5, length: 2),
            NSRange(location: 7, length: 1),
            NSRange(location: 8, length: 2),
        ]
        let halfSurrogateRanges = [
            NSRange(location: 1, length: 1),
            NSRange(location: 2, length: 1),
            NSRange(location: 5, length: 1),
            NSRange(location: 6, length: 1),
            NSRange(location: 8, length: 1),
            NSRange(location: 9, length: 1),
        ]

        for range in validRanges {
            #expect(RichTextUTF16RangeValidator.validate(
                location: range.location,
                length: range.length,
                in: text
            ) != nil)
        }
        for range in halfSurrogateRanges {
            #expect(RichTextUTF16RangeValidator.validate(
                location: range.location,
                length: range.length,
                in: text
            ) == nil)
        }
    }

    @Test
    func `scalar-authored styling keeps font intents encodable for twelve cycles`() throws {
        let expectedUTF16: [UInt16] = [
            0x0041,
            0xD83D, 0xDE00,
            0x0065, 0x0301,
            0xD83D, 0xDC69, 0x200D, 0xD83D, 0xDCBB,
            0x005A,
        ]
        let expectedRuns = [
            RichTextFontIntent.Run(
                utf16Location: 3,
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
            range: NSRange(location: 3, length: 1)
        )
        source.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 4, length: 1)
        )
        source.addAttribute(
            .foregroundColor,
            value: NSColor.systemRed,
            range: NSRange(location: 5, length: 2)
        )
        source.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.double.rawValue,
            range: NSRange(location: 7, length: 1)
        )
        source.addAttribute(
            .backgroundColor,
            value: NSColor.systemBlue,
            range: NSRange(location: 8, length: 2)
        )
        let titled = normalizer.applying(
            .dynamicTextStyle(.title),
            to: NSRange(location: 3, length: 2),
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

        for _ in 0..<12 {
            let content = try #require(document.blocks.first?.content)
            #expect(Array(content.plainText.utf16) == expectedUTF16)
            #expect(content.fontIntentRuns == expectedRuns)

            let encoded = try codec.encodeJSON(document, version: .v1)
            let loaded = codec.loadJSON(encoded, fallbackPlainText: "fallback")
            #expect(loaded.access == .editable)
            #expect(loaded.document.blocks.first?.content.fontIntentRuns == expectedRuns)

            let rendered = try codec.attributedString(from: loaded.document)
            #expect(Array(rendered.string.utf16) == expectedUTF16)
            document = try codec.document(from: rendered, reconciling: loaded.document)
        }
    }

    @Test
    func `public parsing rejects a normalized half-surrogate font run`() throws {
        let source = NSMutableAttributedString(string: "😀")
        source.addAttribute(
            RichTextRuntimeAttributes.fontIntent,
            value: RichTextFontIntentToken(.fixedPointSize(29)),
            range: NSRange(location: 0, length: 1)
        )
        let editable = try codec.editableAttributedString(from: source)

        #expect(throws: RichTextDocumentCodecError.validationFailure) {
            try codec.document(from: editable, reconciling: nil)
        }
    }

    @Test
    func `canonical contraction rejects incompatible constituent attributes`() {
        let decoded = NSMutableAttributedString(string: "e\u{301}")
        decoded.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 1)
        )
        decoded.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 1, length: 1)
        )

        #expect(RichTextRTFTextReconciler().reconcile(decoded, with: "é") == nil)
    }

    @Test
    func `canonical expansion preserves attributes on every authoritative scalar`() throws {
        let decoded = NSAttributedString(
            string: "é",
            attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            ]
        )

        let reconciled = try #require(
            RichTextRTFTextReconciler().reconcile(decoded, with: "e\u{301}")
        )
        #expect(Array(reconciled.string.utf16) == [0x0065, 0x0301])
        for location in 0..<2 {
            #expect(
                reconciled.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int
                    == NSUnderlineStyle.single.rawValue
            )
            #expect(
                reconciled.attribute(
                    .strikethroughStyle,
                    at: location,
                    effectiveRange: nil
                ) as? Int == NSUnderlineStyle.single.rawValue
            )
        }
    }

    @Test
    func `multiple canonical contractions reject the whole attributed mapping`() {
        let decoded = NSMutableAttributedString(string: "A\u{30A}O\u{308}")
        decoded.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 1)
        )
        decoded.addAttribute(
            .strikethroughStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 1, length: 1)
        )
        decoded.addAttribute(
            .backgroundColor,
            value: NSColor.systemBlue,
            range: NSRange(location: 2, length: 2)
        )

        #expect(RichTextRTFTextReconciler().reconcile(decoded, with: "ÅÖ") == nil)
    }

    private func parseNewEditable(_ value: NSAttributedString) throws -> RichTextDocument {
        let editable = try codec.editableAttributedString(from: value)
        return try codec.document(from: editable, reconciling: nil)
    }
}
#endif
