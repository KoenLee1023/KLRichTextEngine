import KLRichTextEngine
import SwiftUI

struct InteractiveReaderView: View {
    @State private var document = RichTextDocument(blocks: [
        .paragraph(RichTextParagraph(id: UUID(uuidString: "82000000-0000-0000-0000-000000000001")!, content: RichTextContent(plainText: "A selectable reading sample"))),
        .checklistItem(RichTextChecklistItem(id: UUID(uuidString: "82000000-0000-0000-0000-000000000002")!, isChecked: false, content: RichTextContent(plainText: "Mark this synthetic task complete"))),
    ])

    var body: some View {
        ScrollView {
            RichTextViewer(document: document, renderingPolicy: RichTextViewerRenderingPolicy(isCompact: true, isSelectable: true), onChecklistToggle: toggleChecklist)
                .padding()
        }
        .navigationTitle("Interactive Reader")
    }

    private func toggleChecklist(_ id: UUID) {
        document = (try? RichTextChecklistMutation().togglingItem(id: id, in: document)) ?? document
    }
}
