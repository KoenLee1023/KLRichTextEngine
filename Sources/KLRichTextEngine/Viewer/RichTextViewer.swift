import Foundation

#if canImport(AppKit)
import AppKit
typealias RichTextViewerPlatformColor = NSColor
#elseif canImport(UIKit)
import UIKit
typealias RichTextViewerPlatformColor = UIColor
#endif

/// The appearance used when resolving viewer colors.
public enum RichTextViewerAppearance: Sendable {
    case light
    case dark
}

/// Rendering options for the SwiftUI viewer on iOS.
public struct RichTextViewerRenderingPolicy: Equatable, Sendable {
    public var isCompact: Bool
    public var isSelectable: Bool

    public init(isCompact: Bool = false, isSelectable: Bool = true) {
        self.isCompact = isCompact
        self.isSelectable = isSelectable
    }
}

public enum RichTextViewerPolicy {
    private static let colorComponentTolerance = CGFloat(1) / 255

    public static var shouldPreserveCustomForegroundColor: Bool { true }

    public static func displayText(for content: RichTextContent) -> String {
        content.rtfData == nil ? content.fallbackMarkdown ?? content.plainText : content.plainText
    }

    public static func shouldRemoveForegroundColor(
        isDefaultForeground: Bool,
        appearance _: RichTextViewerAppearance
    ) -> Bool {
        isDefaultForeground
    }

#if canImport(AppKit) || canImport(UIKit)
    @MainActor
    static func preparedAttributedString(
        from content: RichTextContent,
        defaultForegroundColor: RichTextViewerPlatformColor,
        normalizingFonts: (NSAttributedString) -> NSAttributedString
    ) -> NSAttributedString {
        let annotated = RichTextFontNormalizer().annotatingForEditing(
            RichTextRTFCodec().attributedString(from: content),
            content: content
        )
        let value = NSMutableAttributedString(
            attributedString: normalizingFonts(annotated)
        )
        let fullRange = NSRange(location: 0, length: value.length)
        var missingForegroundRanges: [NSRange] = []
        var defaultForegroundRanges: [NSRange] = []
        value.enumerateAttribute(.foregroundColor, in: fullRange) { color, range, _ in
            guard let color else {
                missingForegroundRanges.append(range)
                return
            }
            guard let platformColor = platformColor(from: color),
                  isDefaultForegroundColor(
                      platformColor,
                      configuredDefault: defaultForegroundColor
                  )
            else {
                return
            }
            defaultForegroundRanges.append(range)
        }
        for range in missingForegroundRanges {
            value.addAttribute(.foregroundColor, value: defaultForegroundColor, range: range)
        }
        for range in defaultForegroundRanges {
            value.removeAttribute(.foregroundColor, range: range)
        }
        return value
    }

    private static func isDefaultForegroundColor(
        _ color: RichTextViewerPlatformColor,
        configuredDefault: RichTextViewerPlatformColor
    ) -> Bool {
        colorsMatch(color, configuredDefault)
    }

    private static func platformColor(
        from value: Any
    ) -> RichTextViewerPlatformColor? {
#if canImport(AppKit)
        value as? NSColor
#elseif canImport(UIKit)
        value as? UIColor
#endif
    }

    private static func colorsMatch(
        _ lhs: RichTextViewerPlatformColor,
        _ rhs: RichTextViewerPlatformColor
    ) -> Bool {
        if lhs.isEqual(rhs) {
            return true
        }
#if canImport(AppKit)
        if lhs.description == rhs.description {
            return true
        }
        guard let resolvedLHS = lhs.usingColorSpace(.deviceRGB),
              let resolvedRHS = rhs.usingColorSpace(.deviceRGB)
        else {
            return false
        }
        return componentsMatch(resolvedLHS.redComponent, resolvedRHS.redComponent)
            && componentsMatch(resolvedLHS.greenComponent, resolvedRHS.greenComponent)
            && componentsMatch(resolvedLHS.blueComponent, resolvedRHS.blueComponent)
            && componentsMatch(resolvedLHS.alphaComponent, resolvedRHS.alphaComponent)
#elseif canImport(UIKit)
        var lhsComponents = (red: CGFloat(), green: CGFloat(), blue: CGFloat(), alpha: CGFloat())
        var rhsComponents = (red: CGFloat(), green: CGFloat(), blue: CGFloat(), alpha: CGFloat())
        guard lhs.getRed(
            &lhsComponents.red,
            green: &lhsComponents.green,
            blue: &lhsComponents.blue,
            alpha: &lhsComponents.alpha
        ), rhs.getRed(
            &rhsComponents.red,
            green: &rhsComponents.green,
            blue: &rhsComponents.blue,
            alpha: &rhsComponents.alpha
        ) else {
            return false
        }
        return componentsMatch(lhsComponents.red, rhsComponents.red)
            && componentsMatch(lhsComponents.green, rhsComponents.green)
            && componentsMatch(lhsComponents.blue, rhsComponents.blue)
            && componentsMatch(lhsComponents.alpha, rhsComponents.alpha)
#endif
    }

    private static func componentsMatch(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) <= colorComponentTolerance
    }
#endif

    public static func performChecklistAction(
        itemID: UUID,
        document: RichTextDocument,
        access: RichTextDocumentAccess,
        onChecklistToggle: (UUID) -> Void
    ) -> RichTextDocument {
        guard access == .editable,
              document.blocks.contains(where: { block in
                  guard case .checklistItem = block else { return false }
                  return block.id == itemID
              })
        else {
            return document
        }
        onChecklistToggle(itemID)
        return document
    }
}

public enum RichTextPackageLocalization {
    public static func string(forKey key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}

#if os(iOS)
import SwiftUI
import UIKit

@MainActor
public struct RichTextViewer: View {
    private let document: RichTextDocument
    private let access: RichTextDocumentAccess
    private let renderingPolicy: RichTextViewerRenderingPolicy
    private let theme: RichTextTheme
    private let onChecklistToggle: ((UUID) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        document: RichTextDocument,
        access: RichTextDocumentAccess = .editable,
        renderingPolicy: RichTextViewerRenderingPolicy = .init(),
        theme: RichTextTheme = .standard,
        onChecklistToggle: ((UUID) -> Void)? = nil
    ) {
        self.document = document
        self.access = access
        self.renderingPolicy = renderingPolicy
        self.theme = theme
        self.onChecklistToggle = onChecklistToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: renderingPolicy.isCompact ? 2 : 8) {
            ForEach(document.blocks) { block in
                row(for: block)
            }
        }
        .fixedSize(horizontal: false, vertical: renderingPolicy.isCompact)
    }

    @ViewBuilder
    private func row(for block: RichTextBlock) -> some View {
        switch block {
        case let .paragraph(paragraph):
            text(for: paragraph.content)
        case let .checklistItem(item):
            HStack(alignment: .firstTextBaseline, spacing: renderingPolicy.isCompact ? 4 : 8) {
                Button {
                    guard let onChecklistToggle else { return }
                    _ = RichTextViewerPolicy.performChecklistAction(
                        itemID: item.id,
                        document: document,
                        access: access,
                        onChecklistToggle: onChecklistToggle
                    )
                } label: {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isChecked ? theme.checkedColor : theme.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(access != .editable || onChecklistToggle == nil)
                text(for: item.content)
                    .strikethrough(item.isChecked)
            }
        }
    }

    @ViewBuilder
    private func text(for content: RichTextContent) -> some View {
        if renderingPolicy.isSelectable {
            Text(styledText(for: content))
                .textSelection(.enabled)
        } else {
            Text(styledText(for: content))
        }
    }

    private func styledText(for content: RichTextContent) -> AttributedString {
        if content.rtfData == nil,
           let markdown = content.fallbackMarkdown,
           let attributed = try? AttributedString(markdown: markdown) {
            return attributed
        }

        return AttributedString(RichTextViewerPolicy.preparedAttributedString(
            from: content,
            defaultForegroundColor: UIColor(theme.defaultTextColor),
            normalizingFonts: { value in
                RichTextFontNormalizer().resolvingFonts(
                    in: value,
                    traits: UITraitCollection(
                        preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
                    )
                )
            }
        ))
    }
}

private extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
#endif
