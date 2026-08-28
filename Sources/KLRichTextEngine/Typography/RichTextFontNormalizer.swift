import Foundation

#if canImport(AppKit)
import AppKit
private typealias RichTextPlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias RichTextPlatformFont = UIFont
#endif

public struct RichTextFontNormalizer: Sendable {
    private let policy: RichTextDynamicTypePolicy

    public init(policy: RichTextDynamicTypePolicy = RichTextDynamicTypePolicy()) {
        self.policy = policy
    }

#if canImport(AppKit)
    @MainActor
    public func applying(
        _ intent: RichTextFontIntent,
        to range: NSRange,
        in value: NSAttributedString,
        contentSizeCategory: RichTextDynamicTypePolicy.ContentSizeCategory
    ) -> NSAttributedString {
        applyingIntent(
            intent,
            to: range,
            in: value,
            resolveFont: { source in
                policy.font(
                    for: intent,
                    preservingSymbolicTraitsOf: source,
                    contentSizeCategory: contentSizeCategory
                )
            }
        )
    }

    @MainActor
    public func resolvingFonts(
        in value: NSAttributedString,
        contentSizeCategory: RichTextDynamicTypePolicy.ContentSizeCategory
    ) -> NSAttributedString {
        resolvingFonts(in: value) { intent, source in
            policy.font(
                for: intent,
                preservingSymbolicTraitsOf: source,
                contentSizeCategory: contentSizeCategory
            )
        }
    }
#elseif canImport(UIKit)
    @MainActor
    public func applying(
        _ intent: RichTextFontIntent,
        to range: NSRange,
        in value: NSAttributedString,
        traits: UITraitCollection
    ) -> NSAttributedString {
        applyingIntent(
            intent,
            to: range,
            in: value,
            resolveFont: { source in
                policy.font(
                    for: intent,
                    preservingSymbolicTraitsOf: source,
                    traits: traits
                )
            }
        )
    }

    @MainActor
    public func resolvingFonts(
        in value: NSAttributedString,
        traits: UITraitCollection
    ) -> NSAttributedString {
        resolvingFonts(in: value) { intent, source in
            policy.font(
                for: intent,
                preservingSymbolicTraitsOf: source,
                traits: traits
            )
        }
    }
#endif

    func annotatingForEditing(
        _ value: NSAttributedString,
        content: RichTextContent
    ) -> NSAttributedString {
        let authoritativeValue = RichTextUTF16CodeUnits.exactlyMatch(
            value.string,
            content.plainText
        )
            ? value
            : NSAttributedString(string: content.plainText)
        guard authoritativeValue.length > 0 else { return authoritativeValue }
        let result = NSMutableAttributedString(attributedString: authoritativeValue)
        let fullRange = NSRange(location: 0, length: result.length)

        if content.fontStorageMode == .dynamicBodyV1 {
            result.addAttribute(
                RichTextRuntimeAttributes.fontIntent,
                value: RichTextFontIntentToken(
                    .dynamicBody,
                    requiresCanonicalDynamicFont: content.rtfData != nil
                        && content.fontIntentRuns.isEmpty
                ),
                range: fullRange
            )
        } else {
            result.addAttribute(
                RichTextRuntimeAttributes.fontIntent,
                value: RichTextFontIntentToken(
                    nil,
                    preservesLegacyStorageMode: true
                ),
                range: fullRange
            )
        }

        guard let validatedRuns = RichTextUTF16RangeValidator.validate(
            content.fontIntentRuns,
            in: content.plainText
        ) else {
            return authoritativeValue
        }
        for (run, range) in zip(content.fontIntentRuns, validatedRuns) {
            result.addAttribute(
                RichTextRuntimeAttributes.fontIntent,
                value: RichTextFontIntentToken(run.intent),
                range: range.nsRange
            )
        }
        RichTextRuntimeDocumentMetadata.transfer(from: value, to: result)
        return result
    }

    @MainActor
    func normalizedForStorage(
        _ value: NSAttributedString
    ) -> RichTextFontStorageNormalization {
        guard value.length > 0 else {
            return RichTextFontStorageNormalization(
                attributedString: value,
                fontStorageMode: .dynamicBodyV1,
                fontIntentRuns: []
            )
        }

        let result = NSMutableAttributedString(attributedString: value)
        let fullRange = NSRange(location: 0, length: result.length)
        var runs: [RichTextFontIntent.Run] = []
        var preservesLegacyStorageMode = true
        result.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let sourceFont = attributes[.font] as? RichTextPlatformFont
            let token = attributes[RichTextRuntimeAttributes.fontIntent]
                as? RichTextFontIntentToken
            preservesLegacyStorageMode = preservesLegacyStorageMode
                && token?.preservesLegacyStorageMode == true
            let intent = storageIntent(from: token, sourceFont: sourceFont)
            let canonical = canonicalFont(for: intent, sourceFont: sourceFont)
            result.addAttribute(.font, value: canonical, range: range)
            result.addAttribute(
                RichTextRuntimeAttributes.fontIntent,
                value: RichTextFontIntentToken(intent),
                range: range
            )

            if intent != .dynamicBody {
                runs.append(
                    RichTextFontIntent.Run(
                        utf16Location: range.location,
                        utf16Length: range.length,
                        intent: intent
                    )
                )
            } else if !policy.hasAuthoredSymbolicTraits(sourceFont) {
                result.removeAttribute(.font, range: range)
            }
        }

        return RichTextFontStorageNormalization(
            attributedString: result,
            fontStorageMode: preservesLegacyStorageMode ? nil : .dynamicBodyV1,
            fontIntentRuns: coalescing(runs, in: result.string)
        )
    }

    @MainActor
    private func applyingIntent(
        _ intent: RichTextFontIntent,
        to range: NSRange,
        in value: NSAttributedString,
        resolveFont: (RichTextPlatformFont?) -> RichTextPlatformFont
    ) -> NSAttributedString {
        guard let safeRange = RichTextUTF16RangeValidator.validate(
            location: range.location,
            length: range.length,
            in: value.string
        ) else {
            return value
        }
        let result = NSMutableAttributedString(attributedString: value)
        result.enumerateAttribute(.font, in: safeRange.nsRange) { candidate, subrange, _ in
            result.addAttribute(
                .font,
                value: resolveFont(candidate as? RichTextPlatformFont),
                range: subrange
            )
            result.addAttribute(
                RichTextRuntimeAttributes.fontIntent,
                value: RichTextFontIntentToken(intent),
                range: subrange
            )
        }
        RichTextRuntimeDocumentMetadata.transfer(from: value, to: result)
        return result
    }

    @MainActor
    private func resolvingFonts(
        in value: NSAttributedString,
        resolveFont: (RichTextFontIntent, RichTextPlatformFont?) -> RichTextPlatformFont
    ) -> NSAttributedString {
        guard value.length > 0 else { return value }
        let result = NSMutableAttributedString(attributedString: value)
        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttributes(in: fullRange) { attributes, range, _ in
            guard let token = attributes[RichTextRuntimeAttributes.fontIntent]
                as? RichTextFontIntentToken
            else {
                return
            }
            guard let intent = token.intent else { return }
            let sourceFont = attributes[.font] as? RichTextPlatformFont
            if token.requiresCanonicalDynamicFont,
               let sourceFont,
               !policy.isCanonicalDynamicFont(sourceFont, for: intent) {
                return
            }
            result.addAttribute(
                .font,
                value: resolveFont(intent, sourceFont),
                range: range
            )
        }
        RichTextRuntimeDocumentMetadata.transfer(from: value, to: result)
        return result
    }

    @MainActor
    private func storageIntent(
        from token: RichTextFontIntentToken?,
        sourceFont: RichTextPlatformFont?
    ) -> RichTextFontIntent {
        guard let token else { return .dynamicBody }
        guard let intent = token.intent else {
            guard let sourceFont else { return .dynamicBody }
            return .fixedPointSize(Double(sourceFont.pointSize))
        }
        if token.requiresCanonicalDynamicFont,
           let sourceFont,
           !policy.isCanonicalDynamicFont(sourceFont, for: intent) {
            return .fixedPointSize(Double(sourceFont.pointSize))
        }
        return intent
    }

    @MainActor
    private func canonicalFont(
        for intent: RichTextFontIntent,
        sourceFont: RichTextPlatformFont?
    ) -> RichTextPlatformFont {
#if canImport(AppKit)
        policy.font(
            for: intent,
            preservingSymbolicTraitsOf: sourceFont,
            contentSizeCategory: .large
        )
#elseif canImport(UIKit)
        policy.font(
            for: intent,
            preservingSymbolicTraitsOf: sourceFont,
            traits: UITraitCollection(preferredContentSizeCategory: .large)
        )
#endif
    }

    private func coalescing(
        _ runs: [RichTextFontIntent.Run],
        in text: String
    ) -> [RichTextFontIntent.Run] {
        guard let validatedRuns = RichTextUTF16RangeValidator.validate(runs, in: text) else {
            return runs
        }
        var result: [RichTextFontIntent.Run] = []
        var lastEnd: Int?
        for (run, range) in zip(runs, validatedRuns) {
            if let last = result.last,
               last.intent == run.intent,
               lastEnd == range.location {
                result[result.count - 1].utf16Length = range.end - last.utf16Location
            } else {
                result.append(run)
            }
            lastEnd = range.end
        }
        return result
    }
}

struct RichTextFontStorageNormalization {
    let attributedString: NSAttributedString
    let fontStorageMode: RichTextFontStorageMode?
    let fontIntentRuns: [RichTextFontIntent.Run]
}
