import KLRichTextEngine
import SwiftUI

struct ComposerView: View {
    @State private var document = RichTextDocument(blocks: [
        .paragraph(RichTextParagraph(id: UUID(uuidString: "81000000-0000-0000-0000-000000000001")!, content: RichTextContent(plainText: "Compose a synthetic document"))),
    ])
    @State private var exportedJSON = ""
    private let codec = RichTextDocumentCodec(validationPolicy: RichTextDocumentValidationPolicy(maximumBlockCount: 12, maximumTextUTF8Bytes: 4_096, maximumEmbeddedDataBytes: 8_192))

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                RichTextEditor(document: $document, access: .editable, configuration: RichTextEditorConfiguration(backend: .automatic), theme: .standard)
                    .frame(minHeight: 220)
                Button("Export JSON") {
                    exportedJSON = (try? String(data: codec.encodeJSON(document, version: .v1), encoding: .utf8)) ?? "Export failed"
                }
                .buttonStyle(.borderedProminent)
                ScrollView { Text(exportedJSON).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding()
            .navigationTitle("Composer")
        }
    }
}
