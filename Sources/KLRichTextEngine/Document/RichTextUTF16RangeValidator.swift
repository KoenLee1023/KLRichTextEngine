import Foundation

struct RichTextValidatedUTF16Range: Equatable, Sendable {
    let location: Int
    let length: Int
    let end: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

enum RichTextUTF16RangeValidator {
    static func validate(
        location: Int,
        length: Int,
        in text: String
    ) -> RichTextValidatedUTF16Range? {
        let upperBound = text.utf16.count
        guard location >= 0,
              length > 0,
              location <= upperBound,
              length <= upperBound - location
        else {
            return nil
        }

        // Derive the endpoint only after subtraction-based bounds checks. This
        // deliberately avoids evaluating attacker-controlled location + length.
        let trailingLength = upperBound - location - length
        let end = upperBound - trailingLength
        guard isScalarBoundary(location, in: text),
              isScalarBoundary(end, in: text)
        else {
            return nil
        }

        return RichTextValidatedUTF16Range(
            location: location,
            length: length,
            end: end
        )
    }

    static func validate(
        _ runs: [RichTextFontIntent.Run],
        in text: String
    ) -> [RichTextValidatedUTF16Range]? {
        var result: [RichTextValidatedUTF16Range] = []
        result.reserveCapacity(runs.count)
        var previousEnd = 0

        for run in runs {
            guard run.utf16Location >= previousEnd,
                  let range = validate(
                      location: run.utf16Location,
                      length: run.utf16Length,
                      in: text
                  )
            else {
                return nil
            }
            result.append(range)
            previousEnd = range.end
        }

        return result
    }

    static func isValidOffset(_ offset: Int, in text: String) -> Bool {
        let upperBound = text.utf16.count
        guard offset >= 0, offset <= upperBound else { return false }
        return isScalarBoundary(offset, in: text)
    }

    private static func isScalarBoundary(_ offset: Int, in text: String) -> Bool {
        let utf16 = text.utf16
        guard offset > 0, offset < utf16.count else { return true }
        let index = utf16.index(utf16.startIndex, offsetBy: offset)
        let previous = utf16[utf16.index(before: index)]
        let current = utf16[index]
        let previousIsHighSurrogate = previous >= 0xD800 && previous <= 0xDBFF
        let currentIsLowSurrogate = current >= 0xDC00 && current <= 0xDFFF
        return !previousIsHighSurrogate || !currentIsLowSurrogate
    }
}
