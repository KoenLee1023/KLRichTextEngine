import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A supported version of the package JSON representation.
public enum RichTextJSONEncodingVersion: Sendable {
    case v0
    case v1
}

/// Errors reported while encoding, decoding, or converting a document.
public enum RichTextDocumentCodecError: Error, Equatable, Sendable {
    case validationFailure
    case readOnly(RichTextReadOnlyReason)
}

/// Converts rich-text documents between supported storage representations.
public struct RichTextDocumentCodec: Sendable {
    public let validationPolicy: RichTextDocumentValidationPolicy

    public init(validationPolicy: RichTextDocumentValidationPolicy) {
        self.validationPolicy = validationPolicy
    }

    public func loadJSON(_ data: Data, fallbackPlainText: String) -> RichTextDocumentLoadResult {
        let fallback = fallbackDocument(plainText: fallbackPlainText)
        let root: [String: Any]

        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return loadResult(fallback, reason: .invalidPayload, originalData: data)
            }
            root = object
        } catch {
            return loadResult(fallback, reason: .invalidPayload, originalData: data)
        }

        let schemaVersion: Int
        if let rawSchemaVersion = root["schemaVersion"] {
            guard let decodedSchemaVersion = rawSchemaVersion as? Int,
                  decodedSchemaVersion >= 0
            else {
                return loadResult(fallback, reason: .invalidPayload, originalData: data)
            }
            schemaVersion = decodedSchemaVersion
        } else {
            schemaVersion = 0
        }

        guard schemaVersion <= 1 else {
            return loadResult(
                fallback,
                reason: .unknownSchema(schemaVersion),
                originalData: data
            )
        }

        do {
            try inspectPayloadBeforeEmbeddedDataDecoding(root)
        } catch RawPayloadError.validationFailure {
            return loadResult(fallback, reason: .validationFailure, originalData: data)
        } catch {
            return loadResult(fallback, reason: .invalidPayload, originalData: data)
        }

        let document: RichTextDocument
        do {
            let decoder = JSONDecoder()
            if schemaVersion == 0 {
                document = try decoder.decode(RichTextDocument.self, from: data)
            } else {
                document = try decoder.decode(VersionedDocument.self, from: data).document
            }
        } catch {
            return loadResult(fallback, reason: .invalidPayload, originalData: data)
        }

        if let unknownMode = document.blocks.lazy.compactMap(\.content.unknownFontStorageModeRawValue).first {
            return RichTextDocumentLoadResult(
                document: document,
                access: .readOnly(.unknownFontStorageMode(unknownMode)),
                originalData: data
            )
        }
        guard isWithinValidationPolicy(document) else {
            return loadResult(fallback, reason: .validationFailure, originalData: data)
        }

        return RichTextDocumentLoadResult(
            document: document,
            access: .editable,
            originalData: data
        )
    }

    public func encodeJSON(
        _ document: RichTextDocument,
        version: RichTextJSONEncodingVersion
    ) throws -> Data {
        if let reason = document.readOnlyReason {
            throw RichTextDocumentCodecError.readOnly(reason)
        }
        if let unknownMode = document.blocks.lazy.compactMap(\.content.unknownFontStorageModeRawValue).first {
            throw RichTextDocumentCodecError.readOnly(.unknownFontStorageMode(unknownMode))
        }
        guard isWithinValidationPolicy(document) else {
            throw RichTextDocumentCodecError.validationFailure
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        switch version {
        case .v0:
            encoder.userInfo[.richTextSchemaVersion] = 0
            return try encoder.encode(document)
        case .v1:
            encoder.userInfo[.richTextSchemaVersion] = 1
            return try encoder.encode(VersionedDocument(schemaVersion: 1, document: document))
        }
    }

    private func fallbackDocument(plainText: String) -> RichTextDocument {
        let fallbackID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        return RichTextDocument(
            blocks: [
                .paragraph(
                    RichTextParagraph(
                        id: fallbackID,
                        content: RichTextContent(plainText: plainText)
                    )
                ),
            ]
        )
    }

    private func loadResult(
        _ fallback: RichTextDocument,
        reason: RichTextReadOnlyReason,
        originalData: Data
    ) -> RichTextDocumentLoadResult {
        RichTextDocumentLoadResult(
            document: fallback,
            access: .readOnly(reason),
            originalData: originalData
        )
    }

    private func inspectPayloadBeforeEmbeddedDataDecoding(_ root: [String: Any]) throws {
        guard let blocks = root["blocks"] as? [[String: Any]] else {
            throw RawPayloadError.invalidPayload
        }
        guard blocks.count <= validationPolicy.maximumBlockCount else {
            throw RawPayloadError.validationFailure
        }

        var totalTextBytes = 0
        var totalEmbeddedBytes = 0
        var blockIDs = Set<UUID>()
        for block in blocks {
            guard let type = block["type"] as? String else {
                throw RawPayloadError.invalidPayload
            }

            let payloadKey: String
            switch type {
            case RichTextBlock.Kind.paragraph.rawValue:
                payloadKey = RichTextBlock.Kind.paragraph.rawValue
            case RichTextBlock.Kind.checklist.rawValue:
                payloadKey = RichTextBlock.Kind.checklist.rawValue
            default:
                throw RawPayloadError.invalidPayload
            }

            guard let payload = block[payloadKey] as? [String: Any],
                  let rawID = payload["id"] as? String,
                  let blockID = UUID(uuidString: rawID),
                  let content = payload["text"] as? [String: Any],
                  let plainText = content["plainText"] as? String
            else {
                throw RawPayloadError.invalidPayload
            }
            guard blockIDs.insert(blockID).inserted else {
                throw RawPayloadError.validationFailure
            }

            totalTextBytes += plainText.utf8.count
            if let fallbackMarkdown = content["fallbackMarkdown"] as? String {
                totalTextBytes += fallbackMarkdown.utf8.count
            } else if content["fallbackMarkdown"] != nil {
                throw RawPayloadError.invalidPayload
            }

            if let encodedRTF = content["rtfData"] as? String {
                let remainingEmbeddedBytes = validationPolicy.maximumEmbeddedDataBytes
                    - totalEmbeddedBytes
                switch Base64Preflight.inspect(
                    encodedRTF.utf8,
                    maximumDecodedBytes: remainingEmbeddedBytes
                ) {
                case let .valid(decodedByteCount):
                    totalEmbeddedBytes += decodedByteCount
                case .invalid:
                    throw RawPayloadError.invalidPayload
                case .exceedsLimit:
                    throw RawPayloadError.validationFailure
                }
            } else if content["rtfData"] != nil {
                throw RawPayloadError.invalidPayload
            }

            guard totalTextBytes <= validationPolicy.maximumTextUTF8Bytes,
                  totalEmbeddedBytes <= validationPolicy.maximumEmbeddedDataBytes
            else {
                throw RawPayloadError.validationFailure
            }
        }
    }

    private func isWithinValidationPolicy(_ document: RichTextDocument) -> Bool {
        guard document.blocks.count <= validationPolicy.maximumBlockCount,
              Set(document.blocks.map(\.id)).count == document.blocks.count
        else {
            return false
        }

        var totalTextBytes = 0
        var totalEmbeddedBytes = 0
        for block in document.blocks {
            totalTextBytes += block.content.plainText.utf8.count
            totalTextBytes += block.content.fallbackMarkdown?.utf8.count ?? 0
            totalEmbeddedBytes += block.content.rtfData?.count ?? 0
            guard hasValidFontIntentRuns(block.content) else { return false }
        }

        return totalTextBytes <= validationPolicy.maximumTextUTF8Bytes
            && totalEmbeddedBytes <= validationPolicy.maximumEmbeddedDataBytes
    }

    private func hasValidFontIntentRuns(_ content: RichTextContent) -> Bool {
        guard RichTextUTF16RangeValidator.validate(
            content.fontIntentRuns,
            in: content.plainText
        ) != nil else {
            return false
        }
        for run in content.fontIntentRuns {
            if case let .fixedPointSize(pointSize) = run.intent,
               (!pointSize.isFinite || pointSize <= 0) {
                return false
            }
        }
        return true
    }
}

public extension RichTextDocumentCodec {
#if canImport(UIKit)
    @MainActor
    func attributedString(
        from document: RichTextDocument,
        traits: UITraitCollection
    ) throws -> NSAttributedString {
        RichTextFontNormalizer().resolvingFonts(
            in: try attributedString(from: document),
            traits: traits
        )
    }
#endif

    func attributedString(from document: RichTextDocument) throws -> NSAttributedString {
        guard document.blocks.allSatisfy({ hasValidFontIntentRuns($0.content) }) else {
            throw RichTextDocumentCodecError.validationFailure
        }
        let provenance = try attributedProvenance(for: document)
        let value = NSMutableAttributedString(string: "")
        let rtfCodec = RichTextRTFCodec()
        let fontNormalizer = RichTextFontNormalizer()
        for (index, block) in document.blocks.enumerated() {
            let blockStart = value.length
            let renderedContent = fontNormalizer.annotatingForEditing(
                rtfCodec.attributedString(from: block.content),
                content: block.content
            )
            if renderedContent.length == 0 {
                value.append(
                    NSAttributedString(
                        string: RichTextRuntimeAttributes.zeroLengthSentinel,
                        attributes: [
                            RichTextRuntimeAttributes.followingEmptyBlockSnapshot:
                                RichTextEmptyBlockSnapshot(block: block),
                        ]
                    )
                )
            } else {
                value.append(renderedContent)
            }
            if index < document.blocks.index(before: document.blocks.endIndex) {
                value.append(NSAttributedString(string: "\n"))
            }

            let blockLength = value.length - blockStart
            guard blockLength > 0 else { continue }
            var attributes: [NSAttributedString.Key: Any] = [
                RichTextRuntimeAttributes.blockID: block.id.uuidString,
                RichTextRuntimeAttributes.blockKind: block.kind.rawValue,
            ]
            if case let .checklistItem(item) = block {
                attributes[RichTextRuntimeAttributes.checklistIsChecked] = item.isChecked
            }
            value.addAttributes(attributes, range: NSRange(location: blockStart, length: blockLength))
        }
        if value.length > 0 {
            value.addAttribute(
                RichTextRuntimeAttributes.documentProvenance,
                value: RichTextAttributedProvenanceToken(provenance),
                range: NSRange(location: 0, length: value.length)
            )
        }
        RichTextRuntimeDocumentMetadata.attach(
            document,
            provenance: provenance,
            to: value
        )
        return value
    }

    /// Marks imported or newly authored attributed content as an editable package value.
    ///
    /// Use this factory before calling ``document(from:reconciling:)`` with a `nil`
    /// previous document. Unmarked attributed values fail closed in that mode. Values
    /// carrying package read-only provenance are rejected instead of being relabeled.
    func editableAttributedString(
        from value: NSAttributedString
    ) throws -> NSAttributedString {
        let runtimeDocument = RichTextRuntimeDocumentMetadata.document(from: value)
        if let reason = runtimeDocument?.readOnlyReason {
            throw RichTextDocumentCodecError.readOnly(reason)
        }
        if let unknownMode = runtimeDocument?.blocks.lazy.compactMap(
            \.content.unknownFontStorageModeRawValue
        ).first {
            throw RichTextDocumentCodecError.readOnly(.unknownFontStorageMode(unknownMode))
        }
        if case let .readOnly(reason, _) = try attributedProvenance(in: value) {
            throw RichTextDocumentCodecError.readOnly(reason)
        }

        if value.length == 0 {
            let emptyDocument = RichTextDocument(
                blocks: [
                    .paragraph(
                        RichTextParagraph(
                            id: UUID(),
                            content: RichTextContent(plainText: "")
                        )
                    ),
                ]
            )
            return try attributedString(from: emptyDocument)
        }

        let result = NSMutableAttributedString(attributedString: value)
        let provenance = RichTextAttributedProvenance.editable
        result.addAttribute(
            RichTextRuntimeAttributes.documentProvenance,
            value: RichTextAttributedProvenanceToken(provenance),
            range: NSRange(location: 0, length: result.length)
        )
        RichTextRuntimeDocumentMetadata.attach(
            runtimeDocument,
            provenance: provenance,
            to: result
        )
        return result
    }

    /// Parses package-provenanced attributed content or reconciles a host edit.
    ///
    /// When `previous` is `nil`, `value` must come from ``attributedString(from:)``
    /// or ``editableAttributedString(from:)``. Supplying an editable previous
    /// document authorizes normal host edits even if runtime attributes were removed.
    @MainActor
    func document(
        from value: NSAttributedString,
        reconciling previous: RichTextDocument?
    ) throws -> RichTextDocument {
        let runtimeDocument = RichTextRuntimeDocumentMetadata.document(from: value)
        if let previous,
           Set(previous.blocks.map(\.id)).count != previous.blocks.count {
            throw RichTextDocumentCodecError.validationFailure
        }
        if let reason = previous?.readOnlyReason {
            throw RichTextDocumentCodecError.readOnly(reason)
        }
        if let unknownMode = previous?.blocks.lazy.compactMap(\.content.unknownFontStorageModeRawValue).first {
            throw RichTextDocumentCodecError.readOnly(.unknownFontStorageMode(unknownMode))
        }
        if let reason = runtimeDocument?.readOnlyReason {
            throw RichTextDocumentCodecError.readOnly(reason)
        }
        if let unknownMode = runtimeDocument?.blocks.lazy.compactMap(
            \.content.unknownFontStorageModeRawValue
        ).first {
            throw RichTextDocumentCodecError.readOnly(.unknownFontStorageMode(unknownMode))
        }

        let provenance = try attributedProvenance(in: value)
        if case let .readOnly(reason, _) = provenance {
            throw RichTextDocumentCodecError.readOnly(reason)
        }
        if previous == nil, provenance != .editable {
            throw RichTextDocumentCodecError.validationFailure
        }
        let rtfCodec = RichTextRTFCodec()
        let parsedBlocks = try attributedLineRanges(in: value.string as NSString).enumerated().map {
            index, lineRange in
            let metadataRange = lineRange.metadataRange
            let encodedPlainText = (value.string as NSString).substring(
                with: lineRange.contentRange
            )
            let inlineEmptySnapshot = firstAttribute(
                RichTextRuntimeAttributes.followingEmptyBlockSnapshot,
                in: lineRange.contentRange,
                value: value
            ) as? RichTextEmptyBlockSnapshot
            let isZeroLengthSentinel = inlineEmptySnapshot != nil
                && encodedPlainText == RichTextRuntimeAttributes.zeroLengthSentinel
            let plainText = isZeroLengthSentinel ? "" : encodedPlainText
            let authoredContentRange = isZeroLengthSentinel
                ? NSRange(location: lineRange.contentRange.location, length: 0)
                : lineRange.contentRange
            let precedingEmptySnapshot: RichTextBlock? = if lineRange.contentRange.length == 0,
                lineRange.contentRange.location > 0 {
                (value.attribute(
                    RichTextRuntimeAttributes.followingEmptyBlockSnapshot,
                    at: lineRange.contentRange.location - 1,
                    effectiveRange: nil
                ) as? RichTextEmptyBlockSnapshot)?.block
            } else {
                nil
            }
            let metadataAtPosition = inlineEmptySnapshot?.block
                ?? precedingEmptySnapshot
                ?? (runtimeDocument?.blocks.indices.contains(index) == true
                    && runtimeDocument?.blocks[index].plainText == plainText
                    ? runtimeDocument?.blocks[index]
                    : nil)
            let runtimeID = firstAttribute(
                RichTextRuntimeAttributes.blockID,
                in: metadataRange,
                value: value
            ).flatMap { rawValue -> UUID? in
                guard let rawValue = rawValue as? String else { return nil }
                return UUID(uuidString: rawValue)
            } ?? metadataAtPosition?.id
            let rawKind = firstAttribute(
                RichTextRuntimeAttributes.blockKind,
                in: metadataRange,
                value: value
            ) as? String
            let previousAtPosition = previous?.blocks.indices.contains(index) == true
                && previous?.blocks[index].plainText == plainText
                && rawKind == nil
                ? previous?.blocks[index]
                : nil
            let kind = rawKind.flatMap(RichTextBlock.Kind.init(rawValue:))
                ?? metadataAtPosition?.kind
                ?? previousAtPosition?.kind
                ?? .paragraph
            let runtimeIsChecked = firstAttribute(
                RichTextRuntimeAttributes.checklistIsChecked,
                in: metadataRange,
                value: value
            ) as? Bool
            let previousIsChecked: Bool
            if case let .checklistItem(item) = previousAtPosition {
                previousIsChecked = item.isChecked
            } else {
                previousIsChecked = false
            }

            let normalized = RichTextFontNormalizer().normalizedForStorage(
                value.attributedSubstring(from: authoredContentRange)
            )
            let serializedContent = try rtfCodec.content(from: normalized.attributedString)
            let parsedContent = RichTextContent(
                plainText: serializedContent.plainText,
                rtfData: serializedContent.rtfData,
                fallbackMarkdown: metadataAtPosition?.content.fallbackMarkdown,
                fontStorageMode: normalized.fontStorageMode,
                fontIntentRuns: normalized.fontIntentRuns
            )
            let metadataContent = metadataAtPosition?.content
            let canReuseMetadataContent = parsedContent.rtfData == nil
                && parsedContent.fontStorageMode == metadataContent?.fontStorageMode
                && parsedContent.fontIntentRuns == metadataContent?.fontIntentRuns
            let content = authoredContentRange.length == 0 && metadataContent != nil
                ? metadataContent ?? parsedContent
                : canReuseMetadataContent
                ? metadataContent ?? parsedContent
                : parsedContent

            return RichTextParsedBlock(
                kind: kind,
                isChecked: runtimeIsChecked
                    ?? metadataAtPosition.flatMap { block -> Bool? in
                        guard case let .checklistItem(item) = block else { return nil }
                        return item.isChecked
                    }
                    ?? previousIsChecked,
                content: content,
                runtimeID: runtimeID
            )
        }
        let document = RichTextBlockIdentityReconciler().reconcile(parsedBlocks, with: previous)
        guard isWithinValidationPolicy(document) else {
            throw RichTextDocumentCodecError.validationFailure
        }
        return document
    }

    private func attributedProvenance(
        for document: RichTextDocument
    ) throws -> RichTextAttributedProvenance {
        if let reason = document.readOnlyReason {
            guard let originalData = document.preservedOriginalData else {
                throw RichTextDocumentCodecError.validationFailure
            }
            return .readOnly(reason: reason, originalData: originalData)
        }
        if let unknownMode = document.blocks.lazy.compactMap(
            \.content.unknownFontStorageModeRawValue
        ).first {
            throw RichTextDocumentCodecError.readOnly(.unknownFontStorageMode(unknownMode))
        }
        return .editable
    }

    private func attributedProvenance(
        in value: NSAttributedString
    ) throws -> RichTextAttributedProvenance? {
        var provenances: [RichTextAttributedProvenance] = []
        if let objectProvenance = RichTextRuntimeDocumentMetadata.provenance(from: value) {
            provenances.append(objectProvenance)
        }

        var hasInvalidToken = false
        if value.length > 0 {
            value.enumerateAttribute(
                RichTextRuntimeAttributes.documentProvenance,
                in: NSRange(location: 0, length: value.length)
            ) { attribute, _, shouldStop in
                guard let attribute else { return }
                guard let token = attribute as? RichTextAttributedProvenanceToken else {
                    hasInvalidToken = true
                    shouldStop.pointee = true
                    return
                }
                provenances.append(token.provenance)
            }
        }

        guard !hasInvalidToken else {
            throw RichTextDocumentCodecError.validationFailure
        }

        var readOnlyProvenance: RichTextAttributedProvenance?
        for provenance in provenances {
            guard case .readOnly = provenance else { continue }
            if let readOnlyProvenance,
               readOnlyProvenance != provenance {
                throw RichTextDocumentCodecError.validationFailure
            }
            readOnlyProvenance = provenance
        }
        if let readOnlyProvenance {
            return readOnlyProvenance
        }
        return provenances.isEmpty ? nil : .editable
    }

    private func firstAttribute(
        _ key: NSAttributedString.Key,
        in range: NSRange,
        value: NSAttributedString
    ) -> Any? {
        guard range.length > 0 else { return nil }
        var result: Any?
        value.enumerateAttribute(key, in: range) { attribute, _, shouldStop in
            guard let attribute else { return }
            result = attribute
            shouldStop.pointee = true
        }
        return result
    }

    private func attributedLineRanges(in string: NSString) -> [AttributedLineRange] {
        let lineFeed: unichar = 10
        let carriageReturn: unichar = 13
        var result: [AttributedLineRange] = []
        var lineStart = 0
        var cursor = 0

        while cursor < string.length {
            let character = string.character(at: cursor)
            guard character == lineFeed || character == carriageReturn else {
                cursor += 1
                continue
            }

            let lineEndingLength: Int
            if character == carriageReturn,
               cursor + 1 < string.length,
               string.character(at: cursor + 1) == lineFeed {
                lineEndingLength = 2
            } else {
                lineEndingLength = 1
            }
            result.append(
                AttributedLineRange(
                    contentRange: NSRange(location: lineStart, length: cursor - lineStart),
                    metadataRange: NSRange(
                        location: lineStart,
                        length: cursor - lineStart + lineEndingLength
                    )
                )
            )
            cursor += lineEndingLength
            lineStart = cursor
        }

        result.append(
            AttributedLineRange(
                contentRange: NSRange(location: lineStart, length: string.length - lineStart),
                metadataRange: NSRange(location: lineStart, length: string.length - lineStart)
            )
        )
        return result
    }
}

private struct AttributedLineRange {
    let contentRange: NSRange
    let metadataRange: NSRange
}

private struct VersionedDocument: Codable {
    let schemaVersion: Int
    let document: RichTextDocument

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case blocks
    }

    init(schemaVersion: Int, document: RichTextDocument) {
        self.schemaVersion = schemaVersion
        self.document = document
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        document = RichTextDocument(blocks: try container.decode([RichTextBlock].self, forKey: .blocks))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(document.blocks, forKey: .blocks)
    }
}

private enum RawPayloadError: Error {
    case invalidPayload
    case validationFailure
}
