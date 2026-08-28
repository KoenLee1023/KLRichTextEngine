public struct RichTextDocumentValidationPolicy: Equatable, Sendable {
    public let maximumBlockCount: Int
    public let maximumTextUTF8Bytes: Int
    public let maximumEmbeddedDataBytes: Int

    public init(
        maximumBlockCount: Int,
        maximumTextUTF8Bytes: Int,
        maximumEmbeddedDataBytes: Int
    ) {
        self.maximumBlockCount = maximumBlockCount
        self.maximumTextUTF8Bytes = maximumTextUTF8Bytes
        self.maximumEmbeddedDataBytes = maximumEmbeddedDataBytes
    }
}
