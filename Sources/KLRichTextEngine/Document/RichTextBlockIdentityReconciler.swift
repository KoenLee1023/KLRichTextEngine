import Foundation

struct RichTextParsedBlock {
    let kind: RichTextBlock.Kind
    let isChecked: Bool
    let content: RichTextContent
    let runtimeID: UUID?
}

struct RichTextBlockIdentityReconciler {
    func reconcile(
        _ parsedBlocks: [RichTextParsedBlock],
        with previous: RichTextDocument?
    ) -> RichTextDocument {
        guard let previous else {
            var usedIDs = Set<UUID>()
            let blocks = parsedBlocks.map { parsedBlock in
                let id: UUID
                if let runtimeID = parsedBlock.runtimeID,
                   usedIDs.insert(runtimeID).inserted {
                    id = runtimeID
                } else {
                    var candidate = UUID()
                    while !usedIDs.insert(candidate).inserted {
                        candidate = UUID()
                    }
                    id = candidate
                }
                return makeBlock(from: parsedBlock, id: id, previousBlock: nil)
            }
            return RichTextDocument(blocks: blocks)
        }

        var assignedIDs = Array<UUID?>(repeating: nil, count: parsedBlocks.count)
        var usedIDs = Set<UUID>()
        let previousByID = Dictionary(
            previous.blocks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for index in parsedBlocks.indices {
            guard let runtimeID = parsedBlocks[index].runtimeID,
                  !usedIDs.contains(runtimeID),
                  let previousBlock = previousByID[runtimeID],
                  previousBlock.kind == parsedBlocks[index].kind
            else {
                continue
            }
            assignedIDs[index] = runtimeID
            usedIDs.insert(runtimeID)
        }

        for index in parsedBlocks.indices where assignedIDs[index] == nil {
            let candidates = previous.blocks.enumerated().filter { _, block in
                !usedIDs.contains(block.id)
                    && block.kind == parsedBlocks[index].kind
                    && block.plainText == parsedBlocks[index].content.plainText
            }
            guard let match = candidates.min(by: {
                distance($0.offset, index) < distance($1.offset, index)
            }) else {
                continue
            }
            assignedIDs[index] = match.element.id
            usedIDs.insert(match.element.id)
        }

        let remainingParsedIndices = parsedBlocks.indices.filter { assignedIDs[$0] == nil }
        let remainingPreviousBlocks = previous.blocks.filter { !usedIDs.contains($0.id) }
        if remainingParsedIndices.count == remainingPreviousBlocks.count {
            for (parsedIndex, previousBlock) in zip(remainingParsedIndices, remainingPreviousBlocks)
            where parsedBlocks[parsedIndex].kind == previousBlock.kind {
                assignedIDs[parsedIndex] = previousBlock.id
                usedIDs.insert(previousBlock.id)
            }
        }

        let blocks = parsedBlocks.indices.map { index in
            let id = assignedIDs[index] ?? UUID()
            return makeBlock(
                from: parsedBlocks[index],
                id: id,
                previousBlock: previousByID[id]
            )
        }
        return RichTextDocument(blocks: blocks)
    }

    private func makeBlock(
        from parsedBlock: RichTextParsedBlock,
        id: UUID,
        previousBlock: RichTextBlock?
    ) -> RichTextBlock {
        let content: RichTextContent
        if parsedBlock.content.rtfData != nil {
            content = parsedBlock.content
        } else if let previousContent = previousBlock?.content,
                  previousContent.plainText == parsedBlock.content.plainText,
                  previousContent.fontStorageMode == parsedBlock.content.fontStorageMode,
                  previousContent.fontIntentRuns == parsedBlock.content.fontIntentRuns {
            content = previousContent
        } else {
            content = parsedBlock.content
        }

        switch parsedBlock.kind {
        case .paragraph:
            return .paragraph(RichTextParagraph(id: id, content: content))
        case .checklist:
            return .checklistItem(
                RichTextChecklistItem(
                    id: id,
                    isChecked: parsedBlock.isChecked,
                    content: content
                )
            )
        }
    }

    private func distance(_ lhs: Int, _ rhs: Int) -> Int {
        lhs >= rhs ? lhs - rhs : rhs - lhs
    }
}

struct RichTextStableBlockIdentity {
    func stabilizingNewBlockIDs(
        in document: RichTextDocument,
        previous: RichTextDocument
    ) -> RichTextDocument {
        let previousIDs = Set(previous.blocks.map(\.id))
        var occupiedIDs = previousIDs
        var result = document
        for index in result.blocks.indices where !previousIDs.contains(result.blocks[index].id) {
            var nonce = 0
            var candidate: UUID
            repeat {
                candidate = deterministicBlockID(
                    previous: previous,
                    block: result.blocks[index],
                    index: index,
                    nonce: nonce
                )
                nonce += 1
            } while occupiedIDs.contains(candidate)
            occupiedIDs.insert(candidate)
            result.blocks[index] = result.blocks[index].replacingID(with: candidate)
        }
        return result
    }

    private func deterministicBlockID(
        previous: RichTextDocument,
        block: RichTextBlock,
        index: Int,
        nonce: Int
    ) -> UUID {
        var bytes: [UInt8] = []
        for previousBlock in previous.blocks {
            bytes.append(contentsOf: previousBlock.id.uuidString.utf8)
            bytes.append(0)
            bytes.append(contentsOf: previousBlock.kind.rawValue.utf8)
            bytes.append(0)
            bytes.append(contentsOf: previousBlock.plainText.utf8)
            bytes.append(0xFF)
        }
        bytes.append(contentsOf: block.kind.rawValue.utf8)
        bytes.append(0)
        bytes.append(contentsOf: block.plainText.utf8)
        bytes.append(0)
        bytes.append(contentsOf: String(index).utf8)
        bytes.append(0)
        bytes.append(contentsOf: String(nonce).utf8)

        let first = fnv1a(bytes, offsetBasis: 0xCBF29CE484222325)
        let second = fnv1a(bytes.reversed(), offsetBasis: 0x84222325CBF29CE4)
        var uuidBytes = [UInt8](repeating: 0, count: 16)
        for byteIndex in 0..<8 {
            let shift = UInt64((7 - byteIndex) * 8)
            uuidBytes[byteIndex] = UInt8(truncatingIfNeeded: first >> shift)
            uuidBytes[byteIndex + 8] = UInt8(truncatingIfNeeded: second >> shift)
        }
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    private func fnv1a(
        _ bytes: some Sequence<UInt8>,
        offsetBasis: UInt64
    ) -> UInt64 {
        var hash = offsetBasis
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x00000100000001B3
        }
        return hash
    }
}

private extension RichTextBlock {
    func replacingID(with id: UUID) -> RichTextBlock {
        switch self {
        case var .paragraph(paragraph):
            paragraph.id = id
            return .paragraph(paragraph)
        case var .checklistItem(item):
            item.id = id
            return .checklistItem(item)
        }
    }
}
