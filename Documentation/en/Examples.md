# Examples

The repository contains three independent iOS demo applications. Each uses the local package through Swift Package Manager.

- `Examples/Composer` edits a document and exports versioned JSON with `RichTextEditor` and `RichTextDocumentCodec`.
- `Examples/InteractiveReader` presents compact selectable content and toggles a checklist through `RichTextViewer` and `RichTextChecklistMutation`.
- `Examples/MigrationLab` loads valid, unknown, and malformed payloads and shows the resulting access state.

The fixtures used by the demos are synthetic. They demonstrate package boundaries and are not production data.
