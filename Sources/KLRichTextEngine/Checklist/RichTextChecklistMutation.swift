import Foundation

public enum RichTextChecklistMutationError: Error, Equatable, Sendable {
    case itemNotFound(UUID)
    case invalidUTF16Offset(Int)
    case readOnly(RichTextReadOnlyReason)
}

/// Applies checklist-specific document mutations.
public struct RichTextChecklistMutation: Sendable {
    public init() {}

    public func togglingItem(id: UUID, in document: RichTextDocument) throws -> RichTextDocument {
        if let reason = document.readOnlyReason {
            throw RichTextChecklistMutationError.readOnly(reason)
        }
        if let unknownMode = document.blocks.lazy.compactMap(\.content.unknownFontStorageModeRawValue).first {
            throw RichTextChecklistMutationError.readOnly(.unknownFontStorageMode(unknownMode))
        }
        var result = document
        guard let index = result.blocks.firstIndex(where: { $0.id == id }),
              case var .checklistItem(item) = result.blocks[index]
        else {
            return document
        }
        guard RichTextUTF16RangeValidator.validate(
            item.content.fontIntentRuns,
            in: item.content.plainText
        ) != nil else {
            throw RichTextChecklistMutationError.readOnly(.invalidPayload)
        }

        item.isChecked.toggle()
        result.blocks[index] = .checklistItem(item)
        return result
    }

    public func pressingReturn(
        inItemWithID id: UUID,
        atUTF16Offset offset: Int,
        in document: RichTextDocument
    ) throws -> RichTextDocument {
        if let reason = document.readOnlyReason {
            throw RichTextChecklistMutationError.readOnly(reason)
        }
        if let unknownMode = document.blocks.lazy.compactMap(\.content.unknownFontStorageModeRawValue).first {
            throw RichTextChecklistMutationError.readOnly(.unknownFontStorageMode(unknownMode))
        }
        guard let blockIndex = document.blocks.firstIndex(where: { $0.id == id }),
              case let .checklistItem(item) = document.blocks[blockIndex]
        else {
            throw RichTextChecklistMutationError.itemNotFound(id)
        }

        guard RichTextUTF16RangeValidator.isValidOffset(
            offset,
            in: item.content.plainText
        ) else {
            throw RichTextChecklistMutationError.invalidUTF16Offset(offset)
        }
        guard RichTextUTF16RangeValidator.validate(
            item.content.fontIntentRuns,
            in: item.content.plainText
        ) != nil else {
            throw RichTextChecklistMutationError.readOnly(.invalidPayload)
        }

        if item.content.plainText.isEmpty {
            var result = document
            result.blocks[blockIndex] = .paragraph(
                RichTextParagraph(id: item.id, content: item.content)
            )
            return result
        }

        let utf16 = item.content.plainText.utf16
        let utf16Index = utf16.index(utf16.startIndex, offsetBy: offset)
        guard let splitIndex = String.Index(utf16Index, within: item.content.plainText) else {
            throw RichTextChecklistMutationError.invalidUTF16Offset(offset)
        }

        let suffix = String(item.content.plainText[splitIndex...])
        let firstContent: RichTextContent
        let secondContent: RichTextContent
        if suffix.isEmpty {
            firstContent = item.content
            secondContent = RichTextContent(
                plainText: "",
                fontStorageMode: item.content.fontStorageMode
            )
        } else {
            let splitContent = try RichTextRTFCodec().split(
                item.content,
                atUTF16Offset: offset
            )
            firstContent = splitContent.prefix
            secondContent = splitContent.suffix
        }

        var result = document
        result.blocks[blockIndex] = .checklistItem(
            RichTextChecklistItem(
                id: item.id,
                isChecked: item.isChecked,
                content: firstContent
            )
        )
        result.blocks.insert(
            .checklistItem(
                RichTextChecklistItem(
                    id: UUID(),
                    isChecked: false,
                    content: secondContent
                )
            ),
            at: result.blocks.index(after: blockIndex)
        )
        return result
    }
}
