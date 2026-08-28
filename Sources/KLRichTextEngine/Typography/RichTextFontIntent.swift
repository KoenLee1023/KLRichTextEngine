import Foundation

/// A semantic font choice that can be resolved without storing a fixed size.
public enum RichTextFontIntent: Equatable, Sendable {
    public enum TextStyle: String, Codable, CaseIterable, Sendable {
        case title
        case heading
        case subheading
        case footnote
        case caption
    }

    case dynamicBody
    case dynamicTextStyle(TextStyle)
    case fixedPointSize(Double)

    public struct Run: Codable, Equatable, Sendable {
        public var utf16Location: Int
        public var utf16Length: Int
        public var intent: RichTextFontIntent

        public init(
            utf16Location: Int,
            utf16Length: Int,
            intent: RichTextFontIntent
        ) {
            self.utf16Location = utf16Location
            self.utf16Length = utf16Length
            self.intent = intent
        }
    }
}

extension RichTextFontIntent: Codable {
    private enum Kind: String, Codable {
        case dynamicBody
        case dynamicTextStyle
        case fixedPointSize
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case textStyle
        case pointSize
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .dynamicBody:
            self = .dynamicBody
        case .dynamicTextStyle:
            self = .dynamicTextStyle(
                try container.decode(TextStyle.self, forKey: .textStyle)
            )
        case .fixedPointSize:
            let pointSize = try container.decode(Double.self, forKey: .pointSize)
            guard pointSize.isFinite, pointSize > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .pointSize,
                    in: container,
                    debugDescription: "A fixed rich-text point size must be finite and positive."
                )
            }
            self = .fixedPointSize(pointSize)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dynamicBody:
            try container.encode(Kind.dynamicBody, forKey: .kind)
        case let .dynamicTextStyle(textStyle):
            try container.encode(Kind.dynamicTextStyle, forKey: .kind)
            try container.encode(textStyle, forKey: .textStyle)
        case let .fixedPointSize(pointSize):
            guard pointSize.isFinite, pointSize > 0 else {
                throw EncodingError.invalidValue(
                    pointSize,
                    EncodingError.Context(
                        codingPath: encoder.codingPath,
                        debugDescription: "A fixed rich-text point size must be finite and positive."
                    )
                )
            }
            try container.encode(Kind.fixedPointSize, forKey: .kind)
            try container.encode(pointSize, forKey: .pointSize)
        }
    }
}

final class RichTextFontIntentToken: NSObject {
    let intent: RichTextFontIntent?
    let requiresCanonicalDynamicFont: Bool
    let preservesLegacyStorageMode: Bool

    init(
        _ intent: RichTextFontIntent?,
        requiresCanonicalDynamicFont: Bool = false,
        preservesLegacyStorageMode: Bool = false
    ) {
        self.intent = intent
        self.requiresCanonicalDynamicFont = requiresCanonicalDynamicFont
        self.preservesLegacyStorageMode = preservesLegacyStorageMode
    }
}
