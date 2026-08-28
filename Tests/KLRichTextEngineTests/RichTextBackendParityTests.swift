#if canImport(AppKit)
import AppKit
import Foundation
import Testing
@testable import KLRichTextEngine

@MainActor
@Suite
struct RichTextBackendParityTests {
    private let codec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: 50,
            maximumTextUTF8Bytes: 100_000,
            maximumEmbeddedDataBytes: 1_000_000
        )
    )

    @Test
    func `identical formatting commands produce equal backend documents`() throws {
        let initial = try initialDocument()
        let engine = RichTextMutationEngine(documentCodec: codec)
        var foundation = try foundationState(from: initial)
        var swift = try swiftState(from: initial)
        let initialIDs = initial.blocks.map(\.id)
        let commands: [(RichTextFormattingCommand, RichTextSelection)] = [
            (.bold, .init(locationUTF16: 1, lengthUTF16: 2)),
            (.italic, .init(locationUTF16: 3, lengthUTF16: 2)),
            (.underline, .init(locationUTF16: 7, lengthUTF16: 1)),
            (.strikethrough, .init(locationUTF16: 5, lengthUTF16: 5)),
            (.textStyle(.title), .init(locationUTF16: 3, lengthUTF16: 2)),
            (.textStyle(.body), .init(locationUTF16: 3, lengthUTF16: 2)),
            (.textStyle(.fixedPointSize(29)), .init(locationUTF16: 5, lengthUTF16: 5)),
            (.clear, .init(locationUTF16: 1, lengthUTF16: 2)),
            (.alignment(.leading), .init(locationUTF16: 0, lengthUTF16: 11)),
            (.alignment(.center), .init(locationUTF16: 0, lengthUTF16: 11)),
            (.alignment(.trailing), .init(locationUTF16: 0, lengthUTF16: 11)),
            (.list(.bulleted), .init(locationUTF16: 0, lengthUTF16: 11)),
            (.list(.numbered), .init(locationUTF16: 0, lengthUTF16: 11)),
        ]

        for (command, selection) in commands {
            foundation.selection = selection
            swift.selection = selection
            try engine.apply(
                command,
                to: &foundation.value,
                document: &foundation.document,
                selection: &foundation.selection
            )
            try engine.apply(
                command,
                to: &swift.value,
                document: &swift.document,
                selection: &swift.selection
            )

            try assertParity(foundation, swift)
            #expect(foundation.document.blocks.map(\.id) == initialIDs)
            try assertEffect(of: command, in: foundation.document)
        }

        foundation.selection = RichTextSelection(locationUTF16: 12, lengthUTF16: 4)
        swift.selection = foundation.selection
        try engine.apply(
            .toggleChecklist,
            to: &foundation.value,
            document: &foundation.document,
            selection: &foundation.selection
        )
        try engine.apply(
            .toggleChecklist,
            to: &swift.value,
            document: &swift.document,
            selection: &swift.selection
        )

        try assertParity(foundation, swift)
        #expect(foundation.document.blocks.map(\.id) == initialIDs)
        #expect(try checklistItem(in: foundation.document).isChecked)

        let rendered = try codec.attributedString(from: foundation.document)
        #expect(rendered.attribute(.foregroundColor, at: 1, effectiveRange: nil) == nil)
        let firstContent = try #require(foundation.document.blocks.first?.content)
        #expect(firstContent.rtfData != nil)
        #expect(firstContent.fontStorageMode == .dynamicBodyV1)
        #expect(firstContent.fontIntentRuns == [
            RichTextFontIntent.Run(
                utf16Location: 5,
                utf16Length: 5,
                intent: .fixedPointSize(29)
            ),
        ])
        try assertStableV1RoundTrips(foundation.document, cycles: 12)
    }

    @Test
    func `plain paste undo snapshot and trailing newline preserve parity`() throws {
        let initial = try initialDocument()
        let engine = RichTextMutationEngine(documentCodec: codec)
        var foundation = try foundationState(from: initial)
        var swift = try swiftState(from: initial)
        foundation.selection = RichTextSelection(locationUTF16: 3, lengthUTF16: 2)
        swift.selection = foundation.selection
        let foundationSnapshot = foundation
        let swiftSnapshot = swift

        try engine.pastePlainText(
            "plain",
            into: &foundation.value,
            document: &foundation.document,
            selection: &foundation.selection
        )
        try engine.pastePlainText(
            "plain",
            into: &swift.value,
            document: &swift.document,
            selection: &swift.selection
        )

        try assertParity(foundation, swift)
        #expect(foundation.selection == RichTextSelection(locationUTF16: 8, lengthUTF16: 0))
        let pasted = try codec.attributedString(from: foundation.document)
        #expect(pasted.attribute(.foregroundColor, at: 3, effectiveRange: nil) == nil)
        let firstContent = try #require(foundation.document.blocks.first?.content)
        #expect(firstContent.fontIntentRuns.isEmpty)

        foundation = foundationSnapshot
        swift = swiftSnapshot
        try assertParity(foundation, swift)
        #expect(foundation.document == initial)

        let end = foundation.document.plainText.utf16.count
        foundation.selection = RichTextSelection(locationUTF16: end, lengthUTF16: 0)
        swift.selection = foundation.selection
        try engine.pastePlainText(
            "\n",
            into: &foundation.value,
            document: &foundation.document,
            selection: &foundation.selection
        )
        try engine.pastePlainText(
            "\n",
            into: &swift.value,
            document: &swift.document,
            selection: &swift.selection
        )

        try assertParity(foundation, swift)
        #expect(foundation.document.blocks.count == 4)
        #expect(foundation.document.blocks.last?.plainText == "")
        #expect(Array(foundation.document.blocks.prefix(3).map(\.id)) == initial.blocks.map(\.id))
        #expect(foundation.selection == RichTextSelection(
            locationUTF16: end + 1,
            lengthUTF16: 0
        ))
        try assertStableV1RoundTrips(foundation.document, cycles: 12)
    }

    @Test
    func `return in checked checklist item uses checklist mutation semantics`() throws {
        var initial = try initialDocument()
        guard case let .checklistItem(item) = initial.blocks[1] else {
            Issue.record("Expected checklist fixture")
            return
        }
        initial.blocks[1] = .checklistItem(
            RichTextChecklistItem(
                id: item.id,
                isChecked: true,
                content: item.content
            )
        )
        let engine = RichTextMutationEngine(documentCodec: codec)
        var state = try foundationState(from: initial)
        state.selection = RichTextSelection(
            locationUTF16: initial.blocks[0].plainText.utf16.count
                + 1
                + item.content.plainText.utf16.count,
            lengthUTF16: 0
        )

        try engine.pastePlainText(
            "\n",
            into: &state.value,
            document: &state.document,
            selection: &state.selection
        )

        #expect(state.document.blocks.count == 4)
        guard case let .checklistItem(original) = state.document.blocks[1],
              case let .checklistItem(inserted) = state.document.blocks[2]
        else {
            Issue.record("Expected adjacent checklist items")
            return
        }
        #expect(original.id == item.id)
        #expect(original.isChecked)
        #expect(original.content.plainText == "Task")
        #expect(!inserted.isChecked)
        #expect(inserted.content.plainText.isEmpty)
        #expect(state.selection.locationUTF16 == 17)
        #expect(state.selection.lengthUTF16 == 0)
    }

    @Test(arguments: [
        RichTextSelection(locationUTF16: 1, lengthUTF16: 1),
        RichTextSelection(locationUTF16: 2, lengthUTF16: 1),
        RichTextSelection(locationUTF16: 5, lengthUTF16: 1),
        RichTextSelection(locationUTF16: 6, lengthUTF16: 1),
        RichTextSelection(locationUTF16: 8, lengthUTF16: 1),
        RichTextSelection(locationUTF16: 9, lengthUTF16: 1),
        RichTextSelection(locationUTF16: -1, lengthUTF16: 1),
        RichTextSelection(locationUTF16: 0, lengthUTF16: -1),
        RichTextSelection(locationUTF16: .max, lengthUTF16: .max),
    ])
    func `invalid selections reject atomically in both adapters`(
        invalidSelection: RichTextSelection
    ) throws {
        let initial = try initialDocument()
        let engine = RichTextMutationEngine(documentCodec: codec)
        var foundation = try foundationState(from: initial)
        var swift = try swiftState(from: initial)
        foundation.selection = invalidSelection
        swift.selection = invalidSelection
        let foundationBefore = foundation
        let swiftBefore = swift

        #expect(throws: RichTextDocumentCodecError.validationFailure) {
            try engine.apply(
                .bold,
                to: &foundation.value,
                document: &foundation.document,
                selection: &foundation.selection
            )
        }
        #expect(throws: RichTextDocumentCodecError.validationFailure) {
            try engine.apply(
                .bold,
                to: &swift.value,
                document: &swift.document,
                selection: &swift.selection
            )
        }

        #expect(foundation.document == foundationBefore.document)
        #expect(foundation.selection == foundationBefore.selection)
        #expect(foundation.value.isEqual(to: foundationBefore.value))
        #expect(swift.document == swiftBefore.document)
        #expect(swift.selection == swiftBefore.selection)
        #expect(swift.value == swiftBefore.value)
    }

    @Test(arguments: [
        ("v99-unknown-schema", RichTextReadOnlyReason.unknownSchema(99)),
        (
            "v0-unknown-font-mode",
            RichTextReadOnlyReason.unknownFontStorageMode("semanticBodyV99")
        ),
    ])
    func `read-only and unknown documents reject mutations atomically`(
        fixtureName: String,
        expectedReason: RichTextReadOnlyReason
    ) throws {
        let data = try fixtureData(named: fixtureName)
        let loaded = codec.loadJSON(data, fallbackPlainText: "fallback")
        #expect(loaded.access == .readOnly(expectedReason))
        let engine = RichTextMutationEngine(documentCodec: codec)
        var value = NSAttributedString(string: loaded.document.plainText)
        var document = loaded.document
        var selection = RichTextSelection(locationUTF16: 0, lengthUTF16: 1)
        let valueBefore = value
        let documentBefore = document
        let selectionBefore = selection

        #expect(throws: RichTextDocumentCodecError.readOnly(expectedReason)) {
            try engine.apply(
                .underline,
                to: &value,
                document: &document,
                selection: &selection
            )
        }

        #expect(value.isEqual(to: valueBefore))
        #expect(document == documentBefore)
        #expect(selection == selectionBefore)
    }

    @Test
    func `body formatting on plain content avoids authored RTF`() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000101"))
        let initial = RichTextDocument(
            blocks: [
                .paragraph(
                    RichTextParagraph(
                        id: id,
                        content: RichTextContent(plainText: "Plain body")
                    )
                ),
            ]
        )
        let engine = RichTextMutationEngine(documentCodec: codec)
        var state = try foundationState(from: initial)
        state.selection = RichTextSelection(locationUTF16: 0, lengthUTF16: 10)
        let directlyMarked = RichTextFontNormalizer().applying(
            .dynamicBody,
            to: NSRange(location: 0, length: 10),
            in: state.value,
            contentSizeCategory: .large
        )
        let normalization = RichTextFontNormalizer().normalizedForStorage(directlyMarked)
        #expect(normalization.fontStorageMode == .dynamicBodyV1)
        let directlyParsed = try codec.document(from: directlyMarked, reconciling: initial)
        #expect(directlyParsed.blocks.first?.content.fontStorageMode == .dynamicBodyV1)

        try engine.apply(
            .textStyle(.body),
            to: &state.value,
            document: &state.document,
            selection: &state.selection
        )

        let content = try #require(state.document.blocks.first?.content)
        #expect(content.rtfData == nil)
        #expect(content.fontStorageMode == .dynamicBodyV1)
        #expect(content.fontIntentRuns.isEmpty)
        _ = try codec.encodeJSON(state.document, version: .v1)
    }

    private func assertParity(
        _ foundation: FoundationAdapterState,
        _ swift: SwiftAdapterState
    ) throws {
        #expect(foundation.document == swift.document)
        #expect(foundation.selection == swift.selection)
        #expect(foundation.value.string == String(swift.value.characters))
        let foundationData = try codec.encodeJSON(foundation.document, version: .v1)
        let swiftData = try codec.encodeJSON(swift.document, version: .v1)
        #expect(foundationData == swiftData)
        #expect(codec.loadJSON(foundationData, fallbackPlainText: "fallback").access == .editable)
        #expect(codec.loadJSON(swiftData, fallbackPlainText: "fallback").access == .editable)
    }

    private func assertStableV1RoundTrips(
        _ expected: RichTextDocument,
        cycles: Int
    ) throws {
        var document = expected
        for _ in 0..<cycles {
            let data = try codec.encodeJSON(document, version: .v1)
            let loaded = codec.loadJSON(data, fallbackPlainText: "fallback")
            #expect(loaded.access == .editable)
            #expect(loaded.document == expected)
            #expect(loaded.document.blocks.map(\.id) == expected.blocks.map(\.id))
            document = loaded.document
        }
    }

    private func initialDocument() throws -> RichTextDocument {
        let paragraphID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000201")
        )
        let checklistID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000202")
        )
        let tailID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000203")
        )
        let text = "A😀e\u{301}👩‍💻Z"
        let attributed = NSMutableAttributedString(string: text)
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemRed,
            range: NSRange(location: 1, length: 2)
        )
        attributed.addAttribute(
            .font,
            value: NSFont.systemFont(ofSize: 17),
            range: NSRange(location: 0, length: attributed.length)
        )
        let rtfData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        return RichTextDocument(
            blocks: [
                .paragraph(
                    RichTextParagraph(
                        id: paragraphID,
                        content: RichTextContent(
                            plainText: text,
                            rtfData: rtfData,
                            fontStorageMode: .dynamicBodyV1
                        )
                    )
                ),
                .checklistItem(
                    RichTextChecklistItem(
                        id: checklistID,
                        isChecked: false,
                        content: RichTextContent(plainText: "Task")
                    )
                ),
                .paragraph(
                    RichTextParagraph(
                        id: tailID,
                        content: RichTextContent(plainText: "Tail")
                    )
                ),
            ]
        )
    }

    private func foundationState(
        from document: RichTextDocument
    ) throws -> FoundationAdapterState {
        FoundationAdapterState(
            value: try codec.attributedString(from: document),
            document: document,
            selection: RichTextSelection(locationUTF16: 0, lengthUTF16: 0)
        )
    }

    private func swiftState(from document: RichTextDocument) throws -> SwiftAdapterState {
        SwiftAdapterState(
            value: AttributedString(try codec.attributedString(from: document)),
            document: document,
            selection: RichTextSelection(locationUTF16: 0, lengthUTF16: 0)
        )
    }

    private func checklistItem(
        in document: RichTextDocument
    ) throws -> RichTextChecklistItem {
        for block in document.blocks {
            if case let .checklistItem(item) = block {
                return item
            }
        }
        Issue.record("Expected checklist item")
        throw RichTextBackendParityTestError.expectedChecklistItem
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "json"
        ))
        return try Data(contentsOf: url)
    }

    private func assertEffect(
        of command: RichTextFormattingCommand,
        in document: RichTextDocument
    ) throws {
        let rendered = try codec.attributedString(from: document)
        switch command {
        case .bold:
            let font = try #require(
                rendered.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
            )
            #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        case .italic:
            let font = try #require(
                rendered.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
            )
            #expect(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        case .underline:
            #expect(
                rendered.attribute(.underlineStyle, at: 7, effectiveRange: nil) as? Int
                    == NSUnderlineStyle.single.rawValue
            )
        case .strikethrough:
            #expect(
                rendered.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) as? Int
                    == NSUnderlineStyle.single.rawValue
            )
        case .clear:
            #expect(rendered.attribute(.foregroundColor, at: 1, effectiveRange: nil) == nil)
            let font = try #require(
                rendered.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
            )
            #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        case let .alignment(alignment):
            let style = try #require(
                rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                    as? NSParagraphStyle
            )
            let expected: NSTextAlignment = switch alignment {
            case .leading: .left
            case .center: .center
            case .trailing: .right
            }
            #expect(style.alignment == expected)
        case let .list(listStyle):
            let style = try #require(
                rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                    as? NSParagraphStyle
            )
            let expected: NSTextList.MarkerFormat = switch listStyle {
            case .bulleted: .disc
            case .numbered: .decimal
            }
            #expect(style.textLists.first?.markerFormat == expected)
        case let .textStyle(textStyle):
            let runs = try #require(document.blocks.first?.content.fontIntentRuns)
            switch textStyle {
            case .body:
                #expect(!runs.contains { $0.utf16Location == 3 })
            case .title:
                #expect(runs.contains {
                    $0.utf16Location == 3
                        && $0.utf16Length == 2
                        && $0.intent == .dynamicTextStyle(.title)
                })
            case .fixedPointSize:
                #expect(runs.contains {
                    $0.utf16Location == 5
                        && $0.utf16Length == 5
                        && $0.intent == .fixedPointSize(29)
                })
            case .heading, .subheading, .footnote:
                Issue.record("Unexpected text style in this command sequence")
            }
        case .toggleChecklist:
            #expect(try checklistItem(in: document).isChecked)
        }
    }
}

private struct FoundationAdapterState {
    var value: NSAttributedString
    var document: RichTextDocument
    var selection: RichTextSelection
}

private struct SwiftAdapterState {
    var value: AttributedString
    var document: RichTextDocument
    var selection: RichTextSelection
}

private enum RichTextBackendParityTestError: Error {
    case expectedChecklistItem
}
#endif
