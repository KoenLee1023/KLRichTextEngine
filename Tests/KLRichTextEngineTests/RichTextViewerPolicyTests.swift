import Foundation
import Testing
@testable import KLRichTextEngine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite
struct RichTextViewerPolicyTests {
    @Test
    func `markdown fallback is used only when rich text is unavailable`() throws {
        let content = RichTextContent(
            plainText: "Plain",
            fallbackMarkdown: "**Markdown**"
        )

        #expect(RichTextViewerPolicy.displayText(for: content) == "**Markdown**")
        #expect(RichTextViewerPolicy.displayText(for: RichTextContent(
            plainText: "Plain",
            rtfData: Data("{\\rtf1 Plain}".utf8),
            fallbackMarkdown: "**Markdown**"
        )) == "Plain")
    }

#if canImport(AppKit)
    @MainActor
    @Test
    func `viewer preparation removes an explicit default foreground and retains custom foreground`() throws {
        let lightContent = try foregroundContent(defaultColor: .black, customColor: .white)
        let darkContent = try foregroundContent(defaultColor: .white, customColor: .black)
        let decodedLightDefault = try #require(
            RichTextRTFCodec().attributedString(from: lightContent)
                .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        let decodedDarkDefault = try #require(
            RichTextRTFCodec().attributedString(from: darkContent)
                .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        let preparedForLight = RichTextViewerPolicy.preparedAttributedString(
            from: lightContent,
            defaultForegroundColor: decodedLightDefault,
            normalizingFonts: { $0 }
        )
        let preparedForDark = RichTextViewerPolicy.preparedAttributedString(
            from: darkContent,
            defaultForegroundColor: decodedDarkDefault,
            normalizingFonts: { $0 }
        )

        #expect(preparedForLight.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
        #expect(preparedForDark.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
        #expect((preparedForLight.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor) == .white)
        #expect((preparedForDark.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor) == .black)
    }

    @MainActor
    @Test
    func `viewer preparation normalizes title fonts for the supplied Dynamic Type category`() throws {
        let content = RichTextContent(
            plainText: "Title",
            fontStorageMode: .dynamicBodyV1,
            fontIntentRuns: [
                .init(
                    utf16Location: 0,
                    utf16Length: 5,
                    intent: .dynamicTextStyle(.title)
                ),
            ]
        )
        let normalizer = RichTextFontNormalizer()
        let policy = RichTextDynamicTypePolicy()
        let prepared = RichTextViewerPolicy.preparedAttributedString(
            from: content,
            defaultForegroundColor: .labelColor,
            normalizingFonts: {
                normalizer.resolvingFonts(
                    in: $0,
                    contentSizeCategory: .accessibilityExtraExtraExtraLarge
                )
            }
        )
        let font = try #require(prepared.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(abs(font.pointSize - policy.pointSize(
            for: .dynamicTextStyle(.title),
            contentSizeCategory: .accessibilityExtraExtraExtraLarge
        )) < 0.01)
    }
#endif

    @MainActor
    @Test
    func `plain paste through mutation engine clears title and checklist inheritance while preserving generic formatting`() throws {
        let titleID = try #require(UUID(uuidString: "80000000-0000-0000-0000-000000000010"))
        let checklistID = try #require(UUID(uuidString: "80000000-0000-0000-0000-000000000011"))
        let document = RichTextDocument(blocks: [
            .paragraph(RichTextParagraph(
                id: titleID,
                content: RichTextContent(
                    plainText: "Title",
                    rtfData: Data(#"{\rtf1\ansi\ul Title\ulnone}"#.utf8),
                    fontStorageMode: .dynamicBodyV1,
                    fontIntentRuns: [
                        .init(utf16Location: 0, utf16Length: 5, intent: .dynamicTextStyle(.title)),
                    ]
                )
            )),
            .checklistItem(RichTextChecklistItem(
                id: checklistID,
                isChecked: false,
                content: RichTextContent(plainText: "Task")
            )),
        ])
        let codec = RichTextDocumentCodec(
            validationPolicy: RichTextDocumentValidationPolicy(
                maximumBlockCount: .max,
                maximumTextUTF8Bytes: .max,
                maximumEmbeddedDataBytes: .max
            )
        )
        let engine = RichTextMutationEngine(documentCodec: codec)
        var value: NSAttributedString = NSMutableAttributedString(
            attributedString: try codec.attributedString(from: document)
        )
        var mutatedDocument = document
        var selection = RichTextSelection(locationUTF16: 0, lengthUTF16: 5)

        try engine.pastePlainText("Body", into: &value, document: &mutatedDocument, selection: &selection)

        let title = try #require(mutatedDocument.blocks.first?.content)
        let titleAttributed = RichTextRTFCodec().attributedString(from: title)
        #expect(title.plainText == "Body")
        #expect(title.fontIntentRuns.isEmpty)
        #expect(titleAttributed.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)

        value = try codec.attributedString(from: mutatedDocument)
        selection = RichTextSelection(locationUTF16: 5, lengthUTF16: 4)
        try engine.pastePlainText("Plain", into: &value, document: &mutatedDocument, selection: &selection)

        #expect(mutatedDocument.blocks.count == 2)
        guard case let .paragraph(pastedChecklist) = mutatedDocument.blocks[1] else {
            Issue.record("Expected plain paste to clear checklist inheritance")
            return
        }
        #expect(pastedChecklist.content.plainText == "Plain")
    }

    @Test
    func `checklist callback reports an editable item without mutating the document`() throws {
        let id = try #require(UUID(uuidString: "80000000-0000-0000-0000-000000000001"))
        let document = RichTextDocument(blocks: [
            .checklistItem(RichTextChecklistItem(
                id: id,
                isChecked: false,
                content: RichTextContent(plainText: "Check")
            )),
        ])
        var receivedID: UUID?

        let documentAfterCallback = RichTextViewerPolicy.performChecklistAction(
            itemID: id,
            document: document,
            access: .editable
        ) { receivedID = $0 }

        #expect(receivedID == id)
        #expect(documentAfterCallback == document)
    }

    @Test
    func `checklist callback ignores an editable paragraph ID`() throws {
        let id = try #require(UUID(uuidString: "80000000-0000-0000-0000-000000000003"))
        let document = RichTextDocument(blocks: [
            .paragraph(RichTextParagraph(id: id, content: RichTextContent(plainText: "Paragraph"))),
        ])
        var callbackWasInvoked = false

        _ = RichTextViewerPolicy.performChecklistAction(
            itemID: id,
            document: document,
            access: .editable
        ) { _ in callbackWasInvoked = true }

        #expect(!callbackWasInvoked)
    }

    @Test
    func `unknown access is always read only for checklist interaction`() throws {
        let id = try #require(UUID(uuidString: "80000000-0000-0000-0000-000000000002"))
        let document = RichTextDocument(blocks: [
            .checklistItem(RichTextChecklistItem(
                id: id,
                isChecked: false,
                content: RichTextContent(plainText: "Protected")
            )),
        ])
        var callbackWasInvoked = false

        let documentAfterAction = RichTextViewerPolicy.performChecklistAction(
            itemID: id,
            document: document,
            access: .readOnly(.unknownSchema(99))
        ) { _ in callbackWasInvoked = true }

        #expect(!callbackWasInvoked)
        #expect(documentAfterAction == document)
    }

    @Test
    func `compact and selectable policies retain their requested rendering mode`() {
        let policy = RichTextViewerRenderingPolicy(isCompact: true, isSelectable: true)

        #expect(policy.isCompact)
        #expect(policy.isSelectable)
    }

    @Test
    func `package localization resolves toolbar strings from its module bundle`() {
        #expect(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.bold") == "Bold")
    }

#if canImport(AppKit)
    private func foregroundContent(
        defaultColor: NSColor,
        customColor: NSColor
    ) throws -> RichTextContent {
        let source = NSMutableAttributedString(string: "Default Custom")
        source.addAttribute(
            .foregroundColor,
            value: defaultColor,
            range: NSRange(location: 0, length: 7)
        )
        source.addAttribute(
            .foregroundColor,
            value: customColor,
            range: NSRange(location: 8, length: 6)
        )
        return RichTextContent(
            plainText: source.string,
            rtfData: try rtfData(from: source)
        )
    }

    private func rtfData(from value: NSAttributedString) throws -> Data {
        try value.data(
            from: NSRange(location: 0, length: value.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
#endif
}
