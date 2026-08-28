import KLRichTextEngine
import SwiftUI

struct MigrationLabView: View {
    private let samples: [(String, Data)] = [
        ("v0", Data(#"{"blocks":[{"type":"paragraph","paragraph":{"id":"83000000-0000-0000-0000-000000000001","text":{"plainText":"Synthetic v0 content"}}}]}"#.utf8)),
        ("unknown schema", Data(#"{"schemaVersion":99,"blocks":[]}"#.utf8)),
        ("malformed", Data("{not-json".utf8)),
    ]
    private let codec = RichTextDocumentCodec(validationPolicy: RichTextDocumentValidationPolicy(maximumBlockCount: 12, maximumTextUTF8Bytes: 4_096, maximumEmbeddedDataBytes: 8_192))

    var body: some View {
        List(samples, id: \.0) { label, data in
            let result = codec.loadJSON(data, fallbackPlainText: "Safe fallback")
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.headline)
                Text(result.document.plainText)
                Text(accessDescription(result.access)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Migration Lab")
    }

    private func accessDescription(_ access: RichTextDocumentAccess) -> String {
        switch access {
        case .editable: "editable"
        case .readOnly: "read-only (source preserved)"
        }
    }
}
