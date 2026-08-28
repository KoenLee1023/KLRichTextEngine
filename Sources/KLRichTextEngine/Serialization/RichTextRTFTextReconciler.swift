import Foundation

enum RichTextUTF16CodeUnits {
    static func exactlyMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf16.elementsEqual(rhs.utf16)
    }
}

struct RichTextRTFTextReconciler {
    func reconcile(
        _ decoded: NSAttributedString,
        with authoritativeText: String
    ) -> NSAttributedString? {
        if RichTextUTF16CodeUnits.exactlyMatch(decoded.string, authoritativeText) {
            return decoded
        }
        guard decoded.string == authoritativeText,
              let segments = canonicalSegments(
                  decoded: decoded.string,
                  authoritative: authoritativeText
              )
        else {
            return nil
        }

        let result = NSMutableAttributedString(string: authoritativeText)
        guard decoded.length > 0 else { return result }

        var mappedRuns: [MappedAttributeRun] = []
        var didFail = false
        decoded.enumerateAttributes(
            in: NSRange(location: 0, length: decoded.length)
        ) { attributes, range, shouldStop in
            guard let mappedRange = mappedRange(
                range,
                decodedLength: decoded.length,
                authoritativeLength: result.length,
                segments: segments
            ) else {
                didFail = true
                shouldStop.pointee = true
                return
            }
            guard mappedRange.length > 0 else { return }
            for existing in mappedRuns where existing.overlaps(mappedRange) {
                guard attributesAreEqual(existing.attributes, attributes) else {
                    didFail = true
                    shouldStop.pointee = true
                    return
                }
            }
            mappedRuns.append(
                MappedAttributeRun(attributes: attributes, range: mappedRange)
            )
        }

        guard !didFail else { return nil }
        for run in mappedRuns {
            result.setAttributes(run.attributes, range: run.range.nsRange)
        }
        return result
    }

    private func canonicalSegments(
        decoded: String,
        authoritative: String
    ) -> [CanonicalSegment]? {
        var result: [CanonicalSegment] = []
        var decodedIndex = decoded.startIndex
        var authoritativeIndex = authoritative.startIndex

        while decodedIndex < decoded.endIndex,
              authoritativeIndex < authoritative.endIndex {
            let decodedNext = decoded.index(after: decodedIndex)
            let authoritativeNext = authoritative.index(after: authoritativeIndex)
            guard decoded[decodedIndex] == authoritative[authoritativeIndex],
                  let decodedStart = utf16Offset(of: decodedIndex, in: decoded),
                  let decodedEnd = utf16Offset(of: decodedNext, in: decoded),
                  let authoritativeStart = utf16Offset(
                      of: authoritativeIndex,
                      in: authoritative
                  ),
                  let authoritativeEnd = utf16Offset(
                      of: authoritativeNext,
                      in: authoritative
                  )
            else {
                return nil
            }
            result.append(
                CanonicalSegment(
                    decodedStart: decodedStart,
                    decodedEnd: decodedEnd,
                    authoritativeStart: authoritativeStart,
                    authoritativeEnd: authoritativeEnd
                )
            )
            decodedIndex = decodedNext
            authoritativeIndex = authoritativeNext
        }

        guard decodedIndex == decoded.endIndex,
              authoritativeIndex == authoritative.endIndex
        else {
            return nil
        }
        return result
    }

    private func utf16Offset(
        of index: String.Index,
        in string: String
    ) -> Int? {
        guard let utf16Index = index.samePosition(in: string.utf16) else {
            return nil
        }
        return string.utf16.distance(from: string.utf16.startIndex, to: utf16Index)
    }

    private func mappedRange(
        _ range: NSRange,
        decodedLength: Int,
        authoritativeLength: Int,
        segments: [CanonicalSegment]
    ) -> MappedUTF16Range? {
        guard range.location >= 0,
              range.length >= 0,
              range.location <= decodedLength,
              range.length <= decodedLength - range.location
        else {
            return nil
        }
        let trailingLength = decodedLength - range.location - range.length
        let decodedEnd = decodedLength - trailingLength
        guard let authoritativeStart = mappedOffset(
                  range.location,
                  edge: .lower,
                  decodedLength: decodedLength,
                  authoritativeLength: authoritativeLength,
                  segments: segments
              ),
              let authoritativeEnd = mappedOffset(
                  decodedEnd,
                  edge: .upper,
                  decodedLength: decodedLength,
                  authoritativeLength: authoritativeLength,
                  segments: segments
              ),
              authoritativeEnd >= authoritativeStart
        else {
            return nil
        }
        return MappedUTF16Range(
            location: authoritativeStart,
            length: authoritativeEnd - authoritativeStart,
            end: authoritativeEnd
        )
    }

    private func mappedOffset(
        _ offset: Int,
        edge: RangeEdge,
        decodedLength: Int,
        authoritativeLength: Int,
        segments: [CanonicalSegment]
    ) -> Int? {
        if offset == decodedLength { return authoritativeLength }

        for segment in segments {
            if offset == segment.decodedStart {
                return segment.authoritativeStart
            }
            if offset == segment.decodedEnd {
                return segment.authoritativeEnd
            }
            guard offset > segment.decodedStart,
                  offset < segment.decodedEnd
            else {
                continue
            }

            let decodedSegmentLength = segment.decodedEnd - segment.decodedStart
            let authoritativeSegmentLength = segment.authoritativeEnd
                - segment.authoritativeStart
            if decodedSegmentLength == authoritativeSegmentLength {
                return segment.authoritativeEnd - (segment.decodedEnd - offset)
            }
            switch edge {
            case .lower:
                return segment.authoritativeStart
            case .upper:
                return segment.authoritativeEnd
            }
        }
        return nil
    }

    private func attributesAreEqual(
        _ lhs: [NSAttributedString.Key: Any],
        _ rhs: [NSAttributedString.Key: Any]
    ) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }
}

private struct MappedAttributeRun {
    let attributes: [NSAttributedString.Key: Any]
    let range: MappedUTF16Range

    func overlaps(_ other: MappedUTF16Range) -> Bool {
        range.location < other.end && other.location < range.end
    }
}

private struct MappedUTF16Range {
    let location: Int
    let length: Int
    let end: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

private struct CanonicalSegment {
    let decodedStart: Int
    let decodedEnd: Int
    let authoritativeStart: Int
    let authoritativeEnd: Int
}

private enum RangeEdge {
    case lower
    case upper
}
