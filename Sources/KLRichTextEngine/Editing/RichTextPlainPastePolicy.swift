import Foundation

public struct RichTextPlainPastePolicy: Sendable {
    public enum InheritedAttribute: Hashable, Sendable {
        case title
        case checklist
        case genericFormatting
    }

    public struct Result: Equatable, Sendable {
        public let text: String
        public let attributes: Set<InheritedAttribute>

        public init(text: String, attributes: Set<InheritedAttribute>) {
            self.text = text
            self.attributes = attributes
        }
    }

    public init() {}

    public func normalizing(
        _ text: String,
        inheritedAttributes: Set<InheritedAttribute> = []
    ) throws -> Result {
        Result(
            text: text,
            attributes: inheritedAttributes.subtracting([.title, .checklist])
        )
    }
}
