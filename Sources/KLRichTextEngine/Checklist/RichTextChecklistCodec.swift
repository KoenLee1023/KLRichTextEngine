import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct RichTextChecklistCodec: Sendable {
    private let documentCodec: RichTextDocumentCodec

    public init() {
        documentCodec = RichTextDocumentCodec(
            validationPolicy: RichTextDocumentValidationPolicy(
                maximumBlockCount: .max,
                maximumTextUTF8Bytes: .max,
                maximumEmbeddedDataBytes: .max
            )
        )
    }

    public func render(_ document: RichTextDocument) throws -> NSAttributedString {
        let renderedDocument = try documentCodec.attributedString(from: document)
        let value = NSMutableAttributedString(attributedString: renderedDocument)
        RichTextRuntimeDocumentMetadata.transfer(from: renderedDocument, to: value)
        let fullRange = NSRange(location: 0, length: value.length)
        var checkedRanges: [NSRange] = []
        value.enumerateAttribute(
            RichTextRuntimeAttributes.checklistIsChecked,
            in: fullRange
        ) { rawIsChecked, range, _ in
            if rawIsChecked as? Bool == true {
                checkedRanges.append(range)
            }
        }
        for range in checkedRanges {
            preserveAuthoredStrikethrough(in: range, value: value)
            value.addAttribute(
                RichTextRuntimeAttributes.checklistCompletionDecoration,
                value: true,
                range: range
            )
            value.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: range
            )
        }
        return value
    }

    @MainActor
    public func parse(
        _ value: NSAttributedString,
        reconciling previous: RichTextDocument?
    ) throws -> RichTextDocument {
        let authoredValue = NSMutableAttributedString(attributedString: value)
        RichTextRuntimeDocumentMetadata.transfer(from: value, to: authoredValue)
        let fullRange = NSRange(location: 0, length: authoredValue.length)
        var completionRanges: [NSRange] = []
        authoredValue.enumerateAttribute(
            RichTextRuntimeAttributes.checklistCompletionDecoration,
            in: fullRange
        ) { marker, range, _ in
            if marker as? Bool == true {
                completionRanges.append(range)
            }
        }
        for range in completionRanges {
            restoreAuthoredStrikethrough(in: range, value: authoredValue)
            authoredValue.removeAttribute(
                RichTextRuntimeAttributes.checklistCompletionDecoration,
                range: range
            )
        }
        return try documentCodec.document(from: authoredValue, reconciling: previous)
    }

    private func preserveAuthoredStrikethrough(
        in range: NSRange,
        value: NSMutableAttributedString
    ) {
        var authoredRuns: [(style: Any, range: NSRange)] = []
        value.enumerateAttribute(.strikethroughStyle, in: range) { style, styleRange, _ in
            if let style {
                authoredRuns.append((style, styleRange))
            }
        }
        for run in authoredRuns {
            value.addAttribute(
                RichTextRuntimeAttributes.authoredStrikethroughStyle,
                value: run.style,
                range: run.range
            )
        }
    }

    private func restoreAuthoredStrikethrough(
        in range: NSRange,
        value: NSMutableAttributedString
    ) {
        var authoredRuns: [(style: Any?, range: NSRange)] = []
        value.enumerateAttribute(
            RichTextRuntimeAttributes.authoredStrikethroughStyle,
            in: range
        ) { authoredStyle, styleRange, _ in
            authoredRuns.append((authoredStyle, styleRange))
        }
        for run in authoredRuns {
            if let authoredStyle = run.style {
                value.addAttribute(
                    .strikethroughStyle,
                    value: authoredStyle,
                    range: run.range
                )
            } else {
                value.removeAttribute(.strikethroughStyle, range: run.range)
            }
            value.removeAttribute(
                RichTextRuntimeAttributes.authoredStrikethroughStyle,
                range: run.range
            )
        }
    }
}
