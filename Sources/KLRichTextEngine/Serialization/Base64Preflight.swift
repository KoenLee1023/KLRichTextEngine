enum Base64Preflight {
    enum Result: Equatable, Sendable {
        case valid(decodedByteCount: Int)
        case invalid
        case exceedsLimit
    }

    static func inspect<Bytes: Sequence>(
        _ bytes: Bytes,
        maximumDecodedBytes: Int
    ) -> Result where Bytes.Element == UInt8 {
        guard maximumDecodedBytes >= 0 else { return .exceedsLimit }

        var iterator = bytes.makeIterator()
        var decodedByteCount = 0
        while let first = iterator.next() {
            guard let second = iterator.next(),
                  let third = iterator.next(),
                  let fourth = iterator.next(),
                  isBase64(first),
                  isBase64(second)
            else {
                return .invalid
            }

            let quartetDecodedByteCount: Int
            let isTerminal: Bool
            if third == equals {
                guard fourth == equals else { return .invalid }
                quartetDecodedByteCount = 1
                isTerminal = true
            } else if fourth == equals {
                guard isBase64(third) else { return .invalid }
                quartetDecodedByteCount = 2
                isTerminal = true
            } else {
                guard isBase64(third), isBase64(fourth) else { return .invalid }
                quartetDecodedByteCount = 3
                isTerminal = false
            }

            guard decodedByteCount <= maximumDecodedBytes - quartetDecodedByteCount else {
                return .exceedsLimit
            }
            decodedByteCount += quartetDecodedByteCount

            if isTerminal {
                return iterator.next() == nil
                    ? .valid(decodedByteCount: decodedByteCount)
                    : .invalid
            }
        }
        return .valid(decodedByteCount: decodedByteCount)
    }

    private static let equals: UInt8 = 61

    private static func isBase64(_ byte: UInt8) -> Bool {
        switch byte {
        case 65 ... 90, 97 ... 122, 48 ... 57, 43, 47:
            true
        default:
            false
        }
    }
}
