# Getting started

KLRichTextEngine is a Swift package for editing, rendering, and validating structured rich-text documents. The package owns document semantics and serialization. The host application owns storage, navigation, and platform integration.

Add the package with Swift Package Manager, then import `KLRichTextEngine`.

```swift
let codec = RichTextDocumentCodec()
let document = RichTextDocument(blocks: [
    .paragraph(RichTextParagraph(content: RichTextContent(plainText: "A note")))
])
let data = try codec.encodeJSON(document, version: .v1)
let loaded = try codec.decodeJSON(data)
```

Use `RichTextEditor` for editable iOS UI and `RichTextViewer` for read-only or compact presentation. Keep `RichTextDocument` as the source of truth and persist the JSON or RTF representation selected by the host.

The package supports iOS 17 or later and macOS 14 or later. `RichTextSwiftUIEditor` is available on iOS 26 or later.
