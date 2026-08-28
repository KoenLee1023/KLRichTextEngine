import Foundation
import Testing

@Suite("Task 10 documentation gate")
struct Task10DocumentationGateTests {
    @Test("all locale guides keep the public API name intact")
    func localeGuidesKeepPublicAPINameIntact() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for locale in ["en", "zh-Hans", "zh-Hant", "ja", "ko"] {
            let url = root.appendingPathComponent("Documentation/" + locale + "/API.md")
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.contains("RichTextDocumentCodec"))
            #expect(!text.contains("房间"))
            #expect(!text.contains("フォールバック"))
        }
    }
}
