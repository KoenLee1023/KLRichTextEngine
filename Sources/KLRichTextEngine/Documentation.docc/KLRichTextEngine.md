# KLRichTextEngine

KLRichTextEngine provides value-based rich-text documents, versioned serialization, deterministic editing operations, and SwiftUI/UIKit/AppKit presentation boundaries.

## A document has three boundaries

``RichTextDocument`` is the value passed between storage, editing, and
presentation. Its blocks and content values describe authored structure rather
than a view hierarchy. ``RichTextDocumentCodec`` converts that structure to a
versioned representation for persistence or transport. Decode through the
codec before presenting a document so the host can handle unsupported values
according to ``RichTextDocumentValidationPolicy``.

Editing is performed by ``RichTextMutationEngine`` and the command types in
the Editing topic. Mutations return new values and do not reach into a view or
database. Undo, autosave, conflict handling, and change detection therefore
remain responsibilities of the host application. ``RichTextSelection``
describes the editor's current range and is not authored content.

Use ``RichTextParagraph`` for ordinary attributed text and
``RichTextChecklistItem`` for checklist semantics. Use
``RichTextFormattingCommand`` for an intentional formatting action and
``RichTextPlainPastePolicy`` when converting unstructured clipboard text.
Typography types describe presentation intent; they do not embed platform
fonts into the document.

## Topics

### Documents

- ``RichTextDocument``
- ``RichTextBlock``
- ``RichTextContent``
- ``RichTextParagraph``
- ``RichTextChecklistItem``

### Serialization

- ``RichTextDocumentCodec``
- ``RichTextDocumentValidationPolicy``
- ``RichTextDocumentLoadResult``
- ``RichTextDocumentAccess``
- ``RichTextJSONEncodingVersion``

### Editing

- ``RichTextMutationEngine``
- ``RichTextChecklistMutation``
- ``RichTextFormattingCommand``
- ``RichTextPlainPastePolicy``
- ``RichTextSelection``

### Typography

- ``RichTextDynamicTypePolicy``
- ``RichTextFontIntent``
- ``RichTextFontNormalizer``
