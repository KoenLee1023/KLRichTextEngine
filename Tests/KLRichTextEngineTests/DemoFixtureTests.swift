import Foundation
import Testing
@testable import KLRichTextEngine

@Suite
struct DemoFixtureTests {
    private let codec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: 12,
            maximumTextUTF8Bytes: 4_096,
            maximumEmbeddedDataBytes: 8_192
        )
    )

    @Test(arguments: ["composer", "interactive-reader", "migration-lab"])
    func `every demo fixture decodes as an editable document`(fixtureName: String) throws {
        let fixtureURL = try #require(Bundle.module.url(forResource: fixtureName, withExtension: "json"))
        let fixtureData = try Data(contentsOf: fixtureURL)
        let result = codec.loadJSON(fixtureData, fallbackPlainText: "Fixture fallback")

        #expect(result.access == .editable)
        #expect(!result.document.blocks.isEmpty)
        #expect(!result.document.plainText.isEmpty)
    }
}
