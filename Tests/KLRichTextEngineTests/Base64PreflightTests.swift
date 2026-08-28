import Testing
@testable import KLRichTextEngine

@Suite
struct Base64PreflightTests {
    @Test
    func `preflight stops consuming once decoded data exceeds its limit`() {
        let counter = ConsumptionCounter()
        let bytes = RepeatingBase64Bytes(count: 1_000_000_000, counter: counter)

        let result = Base64Preflight.inspect(bytes, maximumDecodedBytes: 3)

        #expect(result == .exceedsLimit)
        #expect(counter.value == 8)
    }

    @Test(arguments: [
        ("TQ==", Base64Preflight.Result.valid(decodedByteCount: 1)),
        ("TWE=", .valid(decodedByteCount: 2)),
        ("TWFu", .valid(decodedByteCount: 3)),
        ("T=Fu", .invalid),
        ("TWF", .invalid),
    ])
    func `preflight validates base64 quartets and padding`(
        encoded: String,
        expected: Base64Preflight.Result
    ) {
        #expect(
            Base64Preflight.inspect(encoded.utf8, maximumDecodedBytes: 8) == expected
        )
    }
}

private final class ConsumptionCounter: @unchecked Sendable {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

private struct RepeatingBase64Bytes: Sequence {
    let count: Int
    let counter: ConsumptionCounter

    func makeIterator() -> Iterator {
        Iterator(remaining: count, counter: counter)
    }

    struct Iterator: IteratorProtocol {
        var remaining: Int
        let counter: ConsumptionCounter

        mutating func next() -> UInt8? {
            guard remaining > 0 else { return nil }
            remaining -= 1
            counter.increment()
            return 65
        }
    }
}
