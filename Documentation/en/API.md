# API

`KLRichTextEngine` provides a structured document model, codecs, editing commands, and SwiftUI editor/viewer surfaces. `RichTextDocument` is the persisted source of truth; attributed strings and platform text views are projections.

`RichTextDocument` contains ordered `RichTextBlock` values. `RichTextParagraph` stores attributed content, `RichTextChecklistItem` stores checklist state, and `RichTextContent` defines content and font storage. `RichTextDocumentCodec` reads and writes the JSON representation identified by `RichTextJSONEncodingVersion`.

`RichTextDocumentAccess` and `RichTextDocumentLoadResult` report editable, read-only, and compatibility-limited states. `RichTextMutationEngine` applies `RichTextFormattingCommand` to a `RichTextSelection`. `RichTextChecklistMutation` changes checklist state with typed errors, and `RichTextPlainPastePolicy` defines plain-text insertion.

`RichTextEditor` uses `RichTextEditorConfiguration` and `RichTextEditorBackend`. `RichTextViewer` renders read-only content with `RichTextViewerRenderingPolicy` and `RichTextViewerAppearance`. `RichTextDynamicTypePolicy` and `RichTextFontNormalizer` keep display typography separate from stored intent.

Persistence, undo history, titles, networking, and app commands remain host responsibilities.

