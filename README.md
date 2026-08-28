# KLRichTextEngine

> Languages: [English](README.md) · [简体中文](Documentation/zh-Hans/README.md) · [繁體中文](Documentation/zh-Hant/README.md) · [日本語](Documentation/ja/README.md) · [한국어](Documentation/ko/README.md)

`KLRichTextEngine` stores and edits rich text without reducing the document to a plain string. It provides a Codable document model, attributed-string conversion, checklist mutations, font intent storage, paste normalization, and SwiftUI editor and viewer views.

The package keeps authored structure and unsupported values visible to the host. It does not require the integrating app to adopt one persistence format or one editor backend.

## Document model

`RichTextDocument` contains ordered `RichTextBlock` values and exposes `plainText` for search and previews. `RichTextBlock` can represent paragraphs and checklist items. `RichTextContent` stores plain text, optional RTF data, optional `fallbackMarkdown`, font intent runs, and the font storage mode.

```swift
let content = RichTextContent(
    plainText: "Buy milk",
    rtfData: nil,
    fallbackMarkdown: "Buy milk",
    fontIntentRuns: []
)

let document = RichTextDocument(blocks: [
    .paragraph(RichTextParagraph(id: UUID(), content: content))
])
```

## Editing and checklist behavior

`RichTextMutationEngine` applies `RichTextFormattingCommand` values to a document through `RichTextDocumentCodec`. `RichTextPlainPastePolicy` returns normalized text and the inherited attributes that the host may keep. `RichTextSelection` uses UTF-16 offsets so it can be used directly with Foundation text APIs.

`RichTextChecklistMutation.togglingItem(id:in:)` changes one checklist item. `pressingReturn` handles insertion and continuation at a selection. Errors are reported as `RichTextChecklistMutationError` instead of silently changing an unrelated block.

## Serialization and compatibility

`RichTextDocumentAccess` and `RichTextDocumentLoadResult` let a host distinguish editable, read-only, and incompatible data. The original encoded data is retained in the load result. Unknown font storage modes are exposed through `hasUnknownFontStorageMode`, allowing a host to preserve data while choosing a safe display path.

`RichTextChecklistCodec` converts a document to and from `NSAttributedString` while retaining checklist semantics. `RichTextFontNormalizer` and `RichTextFontIntent` keep semantic text styles separate from the concrete font selected by the current Dynamic Type policy.

## SwiftUI views

`RichTextEditor` and `RichTextViewer` are optional view-layer entry points. `RichTextEditorConfiguration` selects the editor backend and `RichTextTheme` supplies colors. `RichTextViewerRenderingPolicy` controls compact rendering and selection. Applications still own undo management, persistence, navigation, and attachment storage.

## Installation

```swift
dependencies: [
    .package(
        url: "https://github.com/KoenLee1023/KLRichTextEngine.git",
        from: "0.1.0"
    )
]
```

## Demos

- [Composer](Examples/Composer)
- [Interactive reader](Examples/InteractiveReader)
- [Migration lab](Examples/MigrationLab)

## Requirements

- iOS 17 or later
- macOS 14 or later
- Swift 6.0 or later
- MIT License

API Documentation: [DocC](https://labs.wondays.space/documentation/en/klrichtextengine)
