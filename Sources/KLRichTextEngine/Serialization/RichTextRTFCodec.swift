import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum RichTextRTFCodecError: Error {
    case invalidUTF16Offset
    case invalidFontIntentRanges
}

struct RichTextRTFCodec {
    func attributedString(from content: RichTextContent) -> NSAttributedString {
        guard let rtfData = content.rtfData,
              let value = try? NSAttributedString(
                  data: rtfData,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil
              ),
              let reconciled = RichTextRTFTextReconciler().reconcile(
                  value,
                  with: content.plainText
              )
        else {
            return NSAttributedString(string: content.plainText)
        }
        return reconciled
    }

    func content(from value: NSAttributedString) throws -> RichTextContent {
        let authoredValue = NSMutableAttributedString(attributedString: value)
        let fullRange = NSRange(location: 0, length: authoredValue.length)
        for key in RichTextRuntimeAttributes.all {
            authoredValue.removeAttribute(key, range: fullRange)
        }

        guard hasAuthoredAttributes(authoredValue) else {
            return RichTextContent(plainText: authoredValue.string)
        }

        let rtfData = try authoredValue.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        return RichTextContent(plainText: authoredValue.string, rtfData: rtfData)
    }

    func split(
        _ content: RichTextContent,
        atUTF16Offset offset: Int
    ) throws -> (prefix: RichTextContent, suffix: RichTextContent) {
        guard RichTextUTF16RangeValidator.isValidOffset(
            offset,
            in: content.plainText
        ) else {
            throw RichTextRTFCodecError.invalidUTF16Offset
        }
        guard let validatedRuns = RichTextUTF16RangeValidator.validate(
            content.fontIntentRuns,
            in: content.plainText
        ) else {
            throw RichTextRTFCodecError.invalidFontIntentRanges
        }
        let fontIntentRuns = splitFontIntentRuns(
            content.fontIntentRuns,
            validatedRanges: validatedRuns,
            atUTF16Offset: offset
        )
        guard content.rtfData != nil else {
            return plainSplit(
                content,
                atUTF16Offset: offset,
                fontIntentRuns: fontIntentRuns
            )
        }
        let attributed = attributedString(from: content)
        guard RichTextUTF16CodeUnits.exactlyMatch(
            attributed.string,
            content.plainText
        ) else {
            return plainSplit(
                content,
                atUTF16Offset: offset,
                fontIntentRuns: fontIntentRuns
            )
        }

        let prefixValue = attributed.attributedSubstring(
            from: NSRange(location: 0, length: offset)
        )
        let suffixValue = attributed.attributedSubstring(
            from: NSRange(location: offset, length: attributed.length - offset)
        )
        let prefix = try self.content(from: prefixValue)
        let suffix = try self.content(from: suffixValue)
        let fallbackMarkdown = splitFallbackMarkdown(
            content.fallbackMarkdown,
            matching: content.plainText,
            atUTF16Offset: offset
        )
        return (
            RichTextContent(
                plainText: prefix.plainText,
                rtfData: prefix.rtfData,
                fallbackMarkdown: fallbackMarkdown.prefix,
                fontStorageMode: content.fontStorageMode,
                fontIntentRuns: fontIntentRuns.prefix
            ),
            RichTextContent(
                plainText: suffix.plainText,
                rtfData: suffix.rtfData,
                fallbackMarkdown: fallbackMarkdown.suffix,
                fontStorageMode: content.fontStorageMode,
                fontIntentRuns: fontIntentRuns.suffix
            )
        )
    }

    private func plainSplit(
        _ content: RichTextContent,
        atUTF16Offset offset: Int,
        fontIntentRuns: (
            prefix: [RichTextFontIntent.Run],
            suffix: [RichTextFontIntent.Run]
        )
    ) -> (prefix: RichTextContent, suffix: RichTextContent) {
        let text = content.plainText as NSString
        let fallbackMarkdown = splitFallbackMarkdown(
            content.fallbackMarkdown,
            matching: content.plainText,
            atUTF16Offset: offset
        )
        return (
            RichTextContent(
                plainText: text.substring(with: NSRange(location: 0, length: offset)),
                fallbackMarkdown: fallbackMarkdown.prefix,
                fontStorageMode: content.fontStorageMode,
                fontIntentRuns: fontIntentRuns.prefix
            ),
            RichTextContent(
                plainText: text.substring(
                    with: NSRange(location: offset, length: text.length - offset)
                ),
                fallbackMarkdown: fallbackMarkdown.suffix,
                fontStorageMode: content.fontStorageMode,
                fontIntentRuns: fontIntentRuns.suffix
            )
        )
    }

    private func splitFontIntentRuns(
        _ runs: [RichTextFontIntent.Run],
        validatedRanges: [RichTextValidatedUTF16Range],
        atUTF16Offset offset: Int
    ) -> (prefix: [RichTextFontIntent.Run], suffix: [RichTextFontIntent.Run]) {
        var prefix: [RichTextFontIntent.Run] = []
        var suffix: [RichTextFontIntent.Run] = []
        for (run, range) in zip(runs, validatedRanges) {
            let start = range.location
            let end = range.end
            if start < offset {
                prefix.append(
                    RichTextFontIntent.Run(
                        utf16Location: start,
                        utf16Length: min(end, offset) - start,
                        intent: run.intent
                    )
                )
            }
            if end > offset {
                suffix.append(
                    RichTextFontIntent.Run(
                        utf16Location: max(start, offset) - offset,
                        utf16Length: end - max(start, offset),
                        intent: run.intent
                    )
                )
            }
        }
        return (prefix, suffix)
    }

    private func splitFallbackMarkdown(
        _ fallbackMarkdown: String?,
        matching plainText: String,
        atUTF16Offset offset: Int
    ) -> (prefix: String?, suffix: String?) {
        guard let fallbackMarkdown else { return (nil, nil) }

        let fallback = fallbackMarkdown as NSString
        guard fallback.length == (plainText as NSString).length,
              RichTextUTF16RangeValidator.isValidOffset(offset, in: fallbackMarkdown)
        else {
            // Markdown syntax can make source offsets diverge from rendered-text offsets.
            // Retain the authored fallback losslessly on both blocks in that case.
            return (fallbackMarkdown, fallbackMarkdown)
        }

        return (
            fallback.substring(with: NSRange(location: 0, length: offset)),
            fallback.substring(
                with: NSRange(location: offset, length: fallback.length - offset)
            )
        )
    }

    private func hasAuthoredAttributes(_ value: NSAttributedString) -> Bool {
        guard value.length > 0 else { return false }
        var hasAttributes = false
        value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) {
            attributes, _, shouldStop in
            guard !attributes.isEmpty else { return }
            hasAttributes = true
            shouldStop.pointee = true
        }
        return hasAttributes
    }
}
