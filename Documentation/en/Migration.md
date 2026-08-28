# Migrating from an app-local implementation

Keep the app’s persistence layer and domain identifiers. Replace the local document model with `RichTextDocument` at the editor boundary, then use `RichTextDocumentCodec` to read existing JSON or RTF.

1. Decode existing data with an explicit `RichTextDocumentValidationPolicy`.
2. Preserve the returned `RichTextDocumentLoadResult` and inspect `access` before enabling editing.
3. Pass the document to `RichTextEditor` or `RichTextViewer`.
4. Apply changes through `RichTextMutationEngine` or `RichTextChecklistMutation`.
5. Encode only after the host has decided the document is safe to persist.

Do not copy runtime attributed-string attributes into storage. Do not replace stable block IDs during a migration. Unknown schema and unsupported font modes should remain read-only until the host has a deliberate conversion path.
