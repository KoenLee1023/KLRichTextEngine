import Foundation
import ObjectiveC

final class RichTextEmptyBlockSnapshot: NSObject {
    let block: RichTextBlock

    init(block: RichTextBlock) {
        self.block = block
    }
}

enum RichTextAttributedProvenance: Equatable, Sendable {
    case editable
    case readOnly(reason: RichTextReadOnlyReason, originalData: Data)
}

final class RichTextAttributedProvenanceToken: NSObject {
    let provenance: RichTextAttributedProvenance

    init(_ provenance: RichTextAttributedProvenance) {
        self.provenance = provenance
    }
}

enum RichTextRuntimeDocumentMetadata {
    static func attach(
        _ document: RichTextDocument?,
        provenance: RichTextAttributedProvenance,
        to value: NSAttributedString
    ) {
        objc_setAssociatedObject(
            value,
            associationKey,
            Metadata(document: document, provenance: provenance),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func document(from value: NSAttributedString) -> RichTextDocument? {
        (objc_getAssociatedObject(value, associationKey) as? Metadata)?.document
    }

    static func provenance(from value: NSAttributedString) -> RichTextAttributedProvenance? {
        (objc_getAssociatedObject(value, associationKey) as? Metadata)?.provenance
    }

    static func transfer(from source: NSAttributedString, to destination: NSAttributedString) {
        guard let metadata = objc_getAssociatedObject(source, associationKey) as? Metadata else {
            return
        }
        attach(metadata.document, provenance: metadata.provenance, to: destination)
    }

    private static var associationKey: UnsafeRawPointer {
        UnsafeRawPointer(Unmanaged.passUnretained(keyOwner).toOpaque())
    }

    private static let keyOwner = AssociationKeyOwner()

    private final class AssociationKeyOwner: @unchecked Sendable {}

    private final class Metadata: NSObject {
        let document: RichTextDocument?
        let provenance: RichTextAttributedProvenance

        init(
            document: RichTextDocument?,
            provenance: RichTextAttributedProvenance
        ) {
            self.document = document
            self.provenance = provenance
        }
    }
}
