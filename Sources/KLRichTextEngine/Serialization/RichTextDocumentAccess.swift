import Foundation

/// Describes whether a loaded document may be edited.
public enum RichTextDocumentAccess: Equatable, Sendable {
    case editable
    case readOnly(RichTextReadOnlyReason)
}

/// Explains why a loaded document is read-only.
public enum RichTextReadOnlyReason: Equatable, Sendable {
    case unknownSchema(Int)
    case unknownFontStorageMode(String)
    case invalidPayload
    case validationFailure
}

/// A loaded document together with its editing access decision.
public struct RichTextDocumentLoadResult: Equatable, Sendable {
    public let document: RichTextDocument
    public let access: RichTextDocumentAccess
    public let originalData: Data

    public init(
        document: RichTextDocument,
        access: RichTextDocumentAccess,
        originalData: Data
    ) {
        switch access {
        case .editable:
            self.document = document
        case let .readOnly(reason):
            self.document = document.preservingReadOnly(reason: reason, originalData: originalData)
        }
        self.access = access
        self.originalData = originalData
    }
}
