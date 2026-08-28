import Foundation

/// Describes how font information is persisted for rich-text content.
public enum RichTextFontStorageMode: String, Codable, Sendable {
    case dynamicBodyV1
}

/// Text content together with authored typography and optional source data.
public struct RichTextContent: Codable, Equatable, Sendable {
    public var plainText: String
    public var rtfData: Data?
    public var fallbackMarkdown: String?
    public var fontIntentRuns: [RichTextFontIntent.Run]

    public var fontStorageMode: RichTextFontStorageMode? {
        fontStorageModeRawValue.flatMap(RichTextFontStorageMode.init(rawValue:))
    }

    public var hasUnknownFontStorageMode: Bool {
        guard let fontStorageModeRawValue else { return false }
        return RichTextFontStorageMode(rawValue: fontStorageModeRawValue) == nil
    }

    var unknownFontStorageModeRawValue: String? {
        hasUnknownFontStorageMode ? fontStorageModeRawValue : nil
    }

    private var fontStorageModeRawValue: String?

    public init(
        plainText: String,
        rtfData: Data? = nil,
        fallbackMarkdown: String? = nil,
        fontStorageMode: RichTextFontStorageMode? = nil,
        fontIntentRuns: [RichTextFontIntent.Run] = []
    ) {
        self.plainText = plainText
        self.rtfData = rtfData
        self.fallbackMarkdown = fallbackMarkdown
        self.fontIntentRuns = fontIntentRuns
        fontStorageModeRawValue = fontStorageMode?.rawValue
    }

    init(
        plainText: String,
        rtfData: Data?,
        fallbackMarkdown: String?,
        fontStorageModeRawValue: String?,
        fontIntentRuns: [RichTextFontIntent.Run] = []
    ) {
        self.plainText = plainText
        self.rtfData = rtfData
        self.fallbackMarkdown = fallbackMarkdown
        self.fontStorageModeRawValue = fontStorageModeRawValue
        self.fontIntentRuns = fontIntentRuns
    }

    private enum CodingKeys: String, CodingKey {
        case plainText
        case rtfData
        case fallbackMarkdown
        case fontStorageMode
        case fontIntentRuns
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plainText = try container.decode(String.self, forKey: .plainText)
        rtfData = try container.decodeIfPresent(Data.self, forKey: .rtfData)
        fallbackMarkdown = try container.decodeIfPresent(String.self, forKey: .fallbackMarkdown)
        fontStorageModeRawValue = try container.decodeIfPresent(String.self, forKey: .fontStorageMode)
        fontIntentRuns = try container.decodeIfPresent(
            [RichTextFontIntent.Run].self,
            forKey: .fontIntentRuns
        ) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        guard RichTextUTF16RangeValidator.validate(fontIntentRuns, in: plainText) != nil else {
            throw EncodingError.invalidValue(
                fontIntentRuns,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Font intent runs must be ordered, nonempty UTF-16 scalar ranges within plainText."
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(plainText, forKey: .plainText)
        try container.encodeIfPresent(rtfData, forKey: .rtfData)
        try container.encodeIfPresent(fallbackMarkdown, forKey: .fallbackMarkdown)
        try container.encodeIfPresent(fontStorageModeRawValue, forKey: .fontStorageMode)
        if encoder.userInfo[.richTextSchemaVersion] as? Int != 0,
           !fontIntentRuns.isEmpty {
            try container.encode(fontIntentRuns, forKey: .fontIntentRuns)
        }
    }
}

extension CodingUserInfoKey {
    static let richTextSchemaVersion = CodingUserInfoKey(
        rawValue: "dev.nuancery-labs.KLRichTextEngine.schema-version"
    )!
}
