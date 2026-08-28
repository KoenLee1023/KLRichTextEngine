import Foundation

/// An ordered rich-text document whose block IDs remain stable across edits.
public struct RichTextDocument: Codable, Equatable, Sendable {
    public var blocks: [RichTextBlock]
    private var readOnlyPreservation: ReadOnlyPreservation?

    public var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n")
    }

    public var hasUnknownFontStorageMode: Bool {
        blocks.contains { $0.content.hasUnknownFontStorageMode }
    }

    public init(blocks: [RichTextBlock]) {
        self.blocks = blocks
        readOnlyPreservation = nil
    }

    private enum CodingKeys: String, CodingKey {
        case blocks
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blocks = try container.decode([RichTextBlock].self, forKey: .blocks)
        readOnlyPreservation = nil
    }

    public func encode(to encoder: any Encoder) throws {
        if readOnlyPreservation != nil {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "A read-only rich text document cannot be re-encoded."
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blocks, forKey: .blocks)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.blocks == rhs.blocks
            && lhs.readOnlyPreservation == rhs.readOnlyPreservation
    }

    var readOnlyReason: RichTextReadOnlyReason? {
        readOnlyPreservation?.reason
    }

    var preservedOriginalData: Data? {
        readOnlyPreservation?.originalData
    }

    func preservingReadOnly(
        reason: RichTextReadOnlyReason,
        originalData: Data
    ) -> RichTextDocument {
        var result = self
        result.readOnlyPreservation = ReadOnlyPreservation(
            reason: reason,
            originalData: originalData
        )
        return result
    }
}

private struct ReadOnlyPreservation: Equatable, Sendable {
    let reason: RichTextReadOnlyReason
    let originalData: Data
}

/// A document block containing paragraph or checklist content.
public enum RichTextBlock: Codable, Equatable, Identifiable, Sendable {
    case paragraph(RichTextParagraph)
    case checklistItem(RichTextChecklistItem)

    public var id: UUID {
        switch self {
        case let .paragraph(paragraph): paragraph.id
        case let .checklistItem(item): item.id
        }
    }

    public var plainText: String {
        content.plainText
    }

    var content: RichTextContent {
        switch self {
        case let .paragraph(paragraph): paragraph.content
        case let .checklistItem(item): item.content
        }
    }

    enum Kind: String, Codable, Sendable {
        case paragraph
        case checklist
    }

    var kind: Kind {
        switch self {
        case .paragraph: .paragraph
        case .checklistItem: .checklist
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case paragraph
        case checklist
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .paragraph:
            self = .paragraph(try container.decode(RichTextParagraph.self, forKey: .paragraph))
        case .checklist:
            self = .checklistItem(
                try container.decode(RichTextChecklistItem.self, forKey: .checklist)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .paragraph(paragraph):
            try container.encode(Kind.paragraph, forKey: .type)
            try container.encode(paragraph, forKey: .paragraph)
        case let .checklistItem(item):
            try container.encode(Kind.checklist, forKey: .type)
            try container.encode(item, forKey: .checklist)
        }
    }
}

/// A paragraph block with stable identity and rich-text content.
public struct RichTextParagraph: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var content: RichTextContent

    public init(id: UUID, content: RichTextContent) {
        self.id = id
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case content = "text"
    }
}

/// A checklist block with stable identity, checked state, and rich-text content.
public struct RichTextChecklistItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var isChecked: Bool
    public var content: RichTextContent

    public init(id: UUID, isChecked: Bool, content: RichTextContent) {
        self.id = id
        self.isChecked = isChecked
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isChecked
        case content = "text"
    }
}
