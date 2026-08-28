import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Resolves authored font intents against the current content-size category.
public struct RichTextDynamicTypePolicy: Sendable {
    public enum ContentSizeCategory: String, Codable, CaseIterable, Sendable {
        case extraSmall
        case small
        case medium
        case large
        case extraLarge
        case extraExtraLarge
        case extraExtraExtraLarge
        case accessibilityMedium
        case accessibilityLarge
        case accessibilityExtraLarge
        case accessibilityExtraExtraLarge
        case accessibilityExtraExtraExtraLarge
    }

    public init() {}

#if canImport(AppKit)
    public func pointSize(
        for intent: RichTextFontIntent,
        contentSizeCategory: ContentSizeCategory
    ) -> CGFloat {
        switch intent {
        case .dynamicBody:
            scaledPointSize(base: 17, contentSizeCategory: contentSizeCategory)
        case let .dynamicTextStyle(style):
            scaledPointSize(
                base: basePointSize(for: style),
                contentSizeCategory: contentSizeCategory
            )
        case let .fixedPointSize(pointSize):
            CGFloat(max(1, pointSize))
        }
    }

    public func font(
        for intent: RichTextFontIntent,
        preservingSymbolicTraitsOf sourceFont: NSFont?,
        contentSizeCategory: ContentSizeCategory
    ) -> NSFont {
        if case let .fixedPointSize(pointSize) = intent, let sourceFont {
            return NSFont(
                descriptor: sourceFont.fontDescriptor,
                size: CGFloat(max(1, pointSize))
            ) ?? sourceFont
        }

        let pointSize = pointSize(for: intent, contentSizeCategory: contentSizeCategory)
        let base = NSFont.systemFont(ofSize: pointSize)
        guard let sourceFont else { return base }
        let traits = sourceFont.fontDescriptor.symbolicTraits.subtracting(.classMask)
        let descriptor = base.fontDescriptor.withSymbolicTraits(
            base.fontDescriptor.symbolicTraits.union(traits)
        )
        return NSFont(descriptor: descriptor, size: pointSize) ?? base
    }

    func isCanonicalDynamicFont(
        _ font: NSFont,
        for intent: RichTextFontIntent
    ) -> Bool {
        let canonical = self.font(
            for: intent,
            preservingSymbolicTraitsOf: font,
            contentSizeCategory: .large
        )
        let isSystemFamily = font.familyName == canonical.familyName
            || font.familyName == "Helvetica Neue"
        return isSystemFamily && abs(font.pointSize - canonical.pointSize) < 0.01
    }

    func hasAuthoredSymbolicTraits(_ font: NSFont?) -> Bool {
        guard let font else { return false }
        return !font.fontDescriptor.symbolicTraits.subtracting(.classMask).isEmpty
    }

    private func basePointSize(for style: RichTextFontIntent.TextStyle) -> CGFloat {
        switch style {
        case .title: 28
        case .heading: 17
        case .subheading: 15
        case .footnote: 13
        case .caption: 12
        }
    }

    private func scaledPointSize(
        base: CGFloat,
        contentSizeCategory: ContentSizeCategory
    ) -> CGFloat {
        base * scale(for: contentSizeCategory)
    }

    private func scale(for category: ContentSizeCategory) -> CGFloat {
        switch category {
        case .extraSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .extraLarge: 1.12
        case .extraExtraLarge: 1.24
        case .extraExtraExtraLarge: 1.35
        case .accessibilityMedium: 1.64
        case .accessibilityLarge: 1.95
        case .accessibilityExtraLarge: 2.35
        case .accessibilityExtraExtraLarge: 2.76
        case .accessibilityExtraExtraExtraLarge: 3.12
        }
    }
#elseif canImport(UIKit)
    @MainActor
    public func pointSize(
        for intent: RichTextFontIntent,
        contentSizeCategory: ContentSizeCategory
    ) -> CGFloat {
        font(
            for: intent,
            preservingSymbolicTraitsOf: nil,
            traits: UITraitCollection(
                preferredContentSizeCategory: contentSizeCategory.uiContentSizeCategory
            )
        ).pointSize
    }

    @MainActor
    public func font(
        for intent: RichTextFontIntent,
        preservingSymbolicTraitsOf sourceFont: UIFont?,
        traits: UITraitCollection
    ) -> UIFont {
        if case let .fixedPointSize(pointSize) = intent, let sourceFont {
            return UIFont(
                descriptor: sourceFont.fontDescriptor,
                size: CGFloat(max(1, pointSize))
            )
        }

        let base: UIFont
        switch intent {
        case .dynamicBody:
            base = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        case let .dynamicTextStyle(style):
            base = UIFont.preferredFont(
                forTextStyle: style.uiTextStyle,
                compatibleWith: traits
            )
        case let .fixedPointSize(pointSize):
            base = UIFont.systemFont(ofSize: CGFloat(max(1, pointSize)))
        }

        guard let sourceFont else { return base }
        let traits = sourceFont.fontDescriptor.symbolicTraits.subtracting(.classMask)
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(
            base.fontDescriptor.symbolicTraits.union(traits)
        ) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    @MainActor
    func isCanonicalDynamicFont(
        _ font: UIFont,
        for intent: RichTextFontIntent
    ) -> Bool {
        let canonical = self.font(
            for: intent,
            preservingSymbolicTraitsOf: font,
            traits: UITraitCollection(preferredContentSizeCategory: .large)
        )
        let isSystemFamily = font.familyName == canonical.familyName
            || font.familyName == "Helvetica Neue"
        return isSystemFamily && abs(font.pointSize - canonical.pointSize) < 0.01
    }

    func hasAuthoredSymbolicTraits(_ font: UIFont?) -> Bool {
        guard let font else { return false }
        return !font.fontDescriptor.symbolicTraits.subtracting(.classMask).isEmpty
    }
#endif
}

#if canImport(UIKit)
private extension RichTextDynamicTypePolicy.ContentSizeCategory {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .extraSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .extraLarge: .extraLarge
        case .extraExtraLarge: .extraExtraLarge
        case .extraExtraExtraLarge: .extraExtraExtraLarge
        case .accessibilityMedium: .accessibilityMedium
        case .accessibilityLarge: .accessibilityLarge
        case .accessibilityExtraLarge: .accessibilityExtraLarge
        case .accessibilityExtraExtraLarge: .accessibilityExtraExtraLarge
        case .accessibilityExtraExtraExtraLarge: .accessibilityExtraExtraExtraLarge
        }
    }
}

private extension RichTextFontIntent.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .title: .title1
        case .heading: .headline
        case .subheading: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        }
    }
}
#endif
