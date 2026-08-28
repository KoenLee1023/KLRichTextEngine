import Foundation

#if canImport(AppKit)
import AppKit
private typealias RichTextMutationFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias RichTextMutationFont = UIFont
#endif

/// Applies deterministic formatting operations to a rich-text document.
public struct RichTextMutationEngine: Sendable {
    private let documentCodec: RichTextDocumentCodec
    private let checklistCodec = RichTextChecklistCodec()
    private let checklistMutation = RichTextChecklistMutation()
    private let fontNormalizer = RichTextFontNormalizer()
    private let fontPolicy = RichTextDynamicTypePolicy()

    public init(documentCodec: RichTextDocumentCodec) {
        self.documentCodec = documentCodec
    }

    @MainActor
    public func apply(
        _ command: RichTextFormattingCommand,
        to value: inout NSAttributedString,
        document: inout RichTextDocument,
        selection: inout RichTextSelection
    ) throws {
        let output = try applying(command, to: document, selection: selection)
        value = output.value
        document = output.document
        selection = output.selection
    }

    @MainActor
    public func apply(
        _ command: RichTextFormattingCommand,
        to value: inout AttributedString,
        document: inout RichTextDocument,
        selection: inout RichTextSelection
    ) throws {
        let output = try applying(command, to: document, selection: selection)
        value = AttributedString(output.value)
        document = output.document
        selection = output.selection
    }

    @MainActor
    public func pastePlainText(
        _ text: String,
        into value: inout NSAttributedString,
        document: inout RichTextDocument,
        selection: inout RichTextSelection
    ) throws {
        let output = try pastingPlainText(text, into: document, selection: selection)
        value = output.value
        document = output.document
        selection = output.selection
    }

    @MainActor
    public func pastePlainText(
        _ text: String,
        into value: inout AttributedString,
        document: inout RichTextDocument,
        selection: inout RichTextSelection
    ) throws {
        let output = try pastingPlainText(text, into: document, selection: selection)
        value = AttributedString(output.value)
        document = output.document
        selection = output.selection
    }

    @MainActor
    private func applying(
        _ command: RichTextFormattingCommand,
        to document: RichTextDocument,
        selection: RichTextSelection
    ) throws -> RichTextMutationOutput {
        let canonical = try canonicalValue(for: document)
        let range = try validatedRange(selection, in: canonical.string)

        if command == .toggleChecklist {
            let mutatedDocument = try togglingChecklist(
                in: document,
                canonicalValue: canonical,
                selection: selection
            )
            return try validatedOutput(
                document: mutatedDocument,
                preservingIDsFrom: document,
                selection: selection
            )
        }

        guard range.length > 0 || command.appliesToParagraph else {
            return RichTextMutationOutput(
                value: canonical,
                document: document,
                selection: selection
            )
        }

        let result: NSMutableAttributedString
        switch command {
        case .bold:
            result = mutableResolvedValue(canonical)
            toggleFontTrait(.bold, in: range, value: result)
        case .italic:
            result = mutableResolvedValue(canonical)
            toggleFontTrait(.italic, in: range, value: result)
        case .underline:
            result = mutableValue(canonical)
            toggleLineStyle(.underlineStyle, in: range, value: result)
        case .strikethrough:
            result = mutableValue(canonical)
            toggleLineStyle(.strikethroughStyle, in: range, value: result)
        case .clear:
            result = mutableValue(canonical)
            clearAuthoredAttributes(in: range, value: result)
            applyFontIntent(.dynamicBody, in: range, value: result)
        case let .alignment(alignment):
            result = mutableValue(canonical)
            applyAlignment(alignment, in: range, value: result)
        case let .list(style):
            result = mutableValue(canonical)
            applyList(style, in: range, value: result)
        case let .textStyle(style):
            result = mutableValue(canonical)
            applyFontIntent(try style.fontIntent, in: range, value: result)
        case .toggleChecklist:
            preconditionFailure("Handled before attributed mutation")
        }

        let mutatedDocument = try checklistCodec.parse(result, reconciling: document)
        return try validatedOutput(
            document: mutatedDocument,
            preservingIDsFrom: document,
            selection: selection
        )
    }

    @MainActor
    private func pastingPlainText(
        _ text: String,
        into document: RichTextDocument,
        selection: RichTextSelection
    ) throws -> RichTextMutationOutput {
        let canonical = try canonicalValue(for: document)
        let range = try validatedRange(selection, in: canonical.string)
        if text == "\n",
           selection.lengthUTF16 == 0,
           let checklistReturn = checklistReturnTarget(
               in: document,
               atUTF16Offset: selection.locationUTF16
           ) {
            let mutatedDocument = try checklistMutation.pressingReturn(
                inItemWithID: checklistReturn.item.id,
                atUTF16Offset: checklistReturn.localOffset,
                in: document
            )
            let locationDelta = checklistReturn.item.content.plainText.isEmpty ? 0 : 1
            let (newLocation, overflow) = selection.locationUTF16
                .addingReportingOverflow(locationDelta)
            guard !overflow else {
                throw RichTextDocumentCodecError.validationFailure
            }
            return try validatedOutput(
                document: mutatedDocument,
                preservingIDsFrom: document,
                selection: RichTextSelection(
                    locationUTF16: newLocation,
                    lengthUTF16: 0
                )
            )
        }
        let result = mutableValue(canonical)
        let inheritedAttributes = inheritedAttributes(in: canonical, at: range)
        let plainPaste = try RichTextPlainPastePolicy().normalizing(
            text,
            inheritedAttributes: inheritedAttributes
        )
        result.replaceCharacters(
            in: range,
            with: NSAttributedString(
                string: plainPaste.text,
                attributes: replacementAttributes(
                    in: canonical,
                    at: range,
                    inheritedAttributes: inheritedAttributes,
                    retainedAttributes: plainPaste.attributes
                )
            )
        )
        let (newLocation, overflow) = selection.locationUTF16.addingReportingOverflow(
            text.utf16.count
        )
        guard !overflow else {
            throw RichTextDocumentCodecError.validationFailure
        }
        let newSelection = RichTextSelection(
            locationUTF16: newLocation,
            lengthUTF16: 0
        )
        let mutatedDocument = try checklistCodec.parse(result, reconciling: document)
        return try validatedOutput(
            document: mutatedDocument,
            preservingIDsFrom: document,
            selection: newSelection
        )
    }

    private func checklistReturnTarget(
        in document: RichTextDocument,
        atUTF16Offset offset: Int
    ) -> (item: RichTextChecklistItem, localOffset: Int)? {
        var blockStart = 0
        for block in document.blocks {
            let blockLength = block.plainText.utf16.count
            if case let .checklistItem(item) = block,
               offset >= blockStart,
               offset <= blockStart + blockLength {
                return (item, offset - blockStart)
            }
            blockStart += blockLength + 1
        }
        return nil
    }

    private func inheritedAttributes(
        in value: NSAttributedString,
        at range: NSRange
    ) -> Set<RichTextPlainPastePolicy.InheritedAttribute> {
        guard let location = inheritedAttributeLocation(in: value, at: range) else {
            return []
        }
        let attributes = value.attributes(at: location, effectiveRange: nil)
        var result: Set<RichTextPlainPastePolicy.InheritedAttribute> = []
        if let token = attributes[RichTextRuntimeAttributes.fontIntent]
            as? RichTextFontIntentToken,
           token.intent == .dynamicTextStyle(.title) {
            result.insert(.title)
        }
        if attributes[RichTextRuntimeAttributes.blockKind] as? String
            == RichTextBlock.Kind.checklist.rawValue {
            result.insert(.checklist)
        }
        if attributes.keys.contains(where: { key in
            !RichTextRuntimeAttributes.all.contains(key) && key != .font
        }) {
            result.insert(.genericFormatting)
        }
        return result
    }

    private func replacementAttributes(
        in value: NSAttributedString,
        at range: NSRange,
        inheritedAttributes: Set<RichTextPlainPastePolicy.InheritedAttribute>,
        retainedAttributes: Set<RichTextPlainPastePolicy.InheritedAttribute>
    ) -> [NSAttributedString.Key: Any] {
        guard retainedAttributes.contains(.genericFormatting),
              let location = inheritedAttributeLocation(in: value, at: range)
        else {
            return [:]
        }
        var attributes = value.attributes(at: location, effectiveRange: nil)
        for key in RichTextRuntimeAttributes.all {
            attributes.removeValue(forKey: key)
        }
        if inheritedAttributes.contains(.title) {
            attributes.removeValue(forKey: .font)
        }
        return attributes
    }

    private func inheritedAttributeLocation(
        in value: NSAttributedString,
        at range: NSRange
    ) -> Int? {
        guard value.length > 0 else { return nil }
        if range.location < value.length {
            return range.location
        }
        return value.length - 1
    }

    @MainActor
    private func canonicalValue(
        for document: RichTextDocument
    ) throws -> NSAttributedString {
        _ = try documentCodec.encodeJSON(document, version: .v1)
        var result = try checklistCodec.render(document)
        guard result.length > 0 else { return result }
        var intentRuns: [(intent: RichTextFontIntent, range: NSRange)] = []
        result.enumerateAttribute(
            RichTextRuntimeAttributes.fontIntent,
            in: NSRange(location: 0, length: result.length)
        ) { candidate, range, _ in
            guard let intent = (candidate as? RichTextFontIntentToken)?.intent else {
                return
            }
            intentRuns.append((intent, range))
        }
        for run in intentRuns {
#if canImport(AppKit)
            result = fontNormalizer.applying(
                run.intent,
                to: run.range,
                in: result,
                contentSizeCategory: .large
            )
#elseif canImport(UIKit)
            result = fontNormalizer.applying(
                run.intent,
                to: run.range,
                in: result,
                traits: UITraitCollection(preferredContentSizeCategory: .large)
            )
#endif
        }
        return result
    }

    private func validatedOutput(
        document: RichTextDocument,
        preservingIDsFrom previous: RichTextDocument,
        selection: RichTextSelection
    ) throws -> RichTextMutationOutput {
        let stabilized = RichTextStableBlockIdentity().stabilizingNewBlockIDs(
            in: document,
            previous: previous
        )
        _ = try documentCodec.encodeJSON(stabilized, version: .v1)
        return RichTextMutationOutput(
            value: try checklistCodec.render(stabilized),
            document: stabilized,
            selection: selection
        )
    }

    private func validatedRange(
        _ selection: RichTextSelection,
        in text: String
    ) throws -> NSRange {
        let upperBound = text.utf16.count
        guard selection.locationUTF16 >= 0,
              selection.lengthUTF16 >= 0,
              selection.locationUTF16 <= upperBound,
              selection.lengthUTF16 <= upperBound - selection.locationUTF16
        else {
            throw RichTextDocumentCodecError.validationFailure
        }
        let trailingLength = upperBound
            - selection.locationUTF16
            - selection.lengthUTF16
        let end = upperBound - trailingLength
        guard RichTextUTF16RangeValidator.isValidOffset(
                  selection.locationUTF16,
                  in: text
              ),
              RichTextUTF16RangeValidator.isValidOffset(end, in: text)
        else {
            throw RichTextDocumentCodecError.validationFailure
        }
        return NSRange(
            location: selection.locationUTF16,
            length: selection.lengthUTF16
        )
    }

    private func mutableValue(
        _ value: NSAttributedString
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(attributedString: value)
        RichTextRuntimeDocumentMetadata.transfer(from: value, to: result)
        return result
    }

    @MainActor
    private func mutableResolvedValue(
        _ value: NSAttributedString
    ) -> NSMutableAttributedString {
#if canImport(AppKit)
        mutableValue(
            fontNormalizer.resolvingFonts(
                in: value,
                contentSizeCategory: .large
            )
        )
#elseif canImport(UIKit)
        mutableValue(
            fontNormalizer.resolvingFonts(
                in: value,
                traits: UITraitCollection(preferredContentSizeCategory: .large)
            )
        )
#endif
    }

    @MainActor
    private func applyFontIntent(
        _ intent: RichTextFontIntent,
        in range: NSRange,
        value: NSMutableAttributedString
    ) {
#if canImport(AppKit)
        let applied = fontNormalizer.applying(
            intent,
            to: range,
            in: value,
            contentSizeCategory: .large
        )
#elseif canImport(UIKit)
        let applied = fontNormalizer.applying(
            intent,
            to: range,
            in: value,
            traits: UITraitCollection(preferredContentSizeCategory: .large)
        )
#endif
        value.setAttributedString(applied)
        RichTextRuntimeDocumentMetadata.transfer(from: applied, to: value)
    }

    @MainActor
    private func toggleFontTrait(
        _ trait: RichTextMutationFontTrait,
        in range: NSRange,
        value: NSMutableAttributedString
    ) {
        var runs: [(font: RichTextMutationFont, range: NSRange)] = []
        value.enumerateAttribute(.font, in: range) { candidate, subrange, _ in
            runs.append((candidate as? RichTextMutationFont ?? defaultBodyFont(), subrange))
        }
        guard !runs.isEmpty else { return }
        let shouldRemove = runs.allSatisfy { hasFontTrait(trait, font: $0.font) }
        for run in runs {
            value.addAttribute(
                .font,
                value: font(run.font, changing: trait, shouldRemove: shouldRemove),
                range: run.range
            )
        }
    }

    @MainActor
    private func defaultBodyFont() -> RichTextMutationFont {
#if canImport(AppKit)
        fontPolicy.font(
            for: .dynamicBody,
            preservingSymbolicTraitsOf: nil,
            contentSizeCategory: .large
        )
#elseif canImport(UIKit)
        fontPolicy.font(
            for: .dynamicBody,
            preservingSymbolicTraitsOf: nil,
            traits: UITraitCollection(preferredContentSizeCategory: .large)
        )
#endif
    }

    private func hasFontTrait(
        _ trait: RichTextMutationFontTrait,
        font: RichTextMutationFont
    ) -> Bool {
#if canImport(AppKit)
        let traits = NSFontManager.shared.traits(of: font)
        return switch trait {
        case .bold: traits.contains(.boldFontMask)
        case .italic: traits.contains(.italicFontMask)
        }
#elseif canImport(UIKit)
        let traits = font.fontDescriptor.symbolicTraits
        return switch trait {
        case .bold: traits.contains(.traitBold)
        case .italic: traits.contains(.traitItalic)
        }
#endif
    }

    private func font(
        _ source: RichTextMutationFont,
        changing trait: RichTextMutationFontTrait,
        shouldRemove: Bool
    ) -> RichTextMutationFont {
#if canImport(AppKit)
        let mask: NSFontTraitMask = switch trait {
        case .bold: .boldFontMask
        case .italic: .italicFontMask
        }
        return shouldRemove
            ? NSFontManager.shared.convert(source, toNotHaveTrait: mask)
            : NSFontManager.shared.convert(source, toHaveTrait: mask)
#elseif canImport(UIKit)
        let symbolicTrait: UIFontDescriptor.SymbolicTraits = switch trait {
        case .bold: .traitBold
        case .italic: .traitItalic
        }
        let traits = shouldRemove
            ? source.fontDescriptor.symbolicTraits.subtracting(symbolicTrait)
            : source.fontDescriptor.symbolicTraits.union(symbolicTrait)
        guard let descriptor = source.fontDescriptor.withSymbolicTraits(traits) else {
            return source
        }
        return UIFont(descriptor: descriptor, size: source.pointSize)
#endif
    }

    private func toggleLineStyle(
        _ key: NSAttributedString.Key,
        in range: NSRange,
        value: NSMutableAttributedString
    ) {
        var hasRuns = false
        var everyRunIsStyled = true
        value.enumerateAttribute(key, in: range) { candidate, _, _ in
            hasRuns = true
            let rawValue = (candidate as? NSNumber)?.intValue ?? candidate as? Int ?? 0
            everyRunIsStyled = everyRunIsStyled && rawValue != 0
        }
        if hasRuns && everyRunIsStyled {
            value.removeAttribute(key, range: range)
        } else {
            value.addAttribute(
                key,
                value: NSUnderlineStyle.single.rawValue,
                range: range
            )
        }
    }

    private func clearAuthoredAttributes(
        in range: NSRange,
        value: NSMutableAttributedString
    ) {
        let runtimeKeys = Set(RichTextRuntimeAttributes.all)
        var authoredKeys = Set<NSAttributedString.Key>()
        value.enumerateAttributes(in: range) { attributes, _, _ in
            authoredKeys.formUnion(attributes.keys.filter { !runtimeKeys.contains($0) })
        }
        for key in authoredKeys {
            value.removeAttribute(key, range: range)
        }
    }

    private func applyAlignment(
        _ alignment: RichTextAlignment,
        in range: NSRange,
        value: NSMutableAttributedString
    ) {
        let paragraphRange = (value.string as NSString).paragraphRange(for: range)
        guard paragraphRange.length > 0 else { return }
        let style = mutableParagraphStyle(at: paragraphRange.location, in: value)
        style.alignment = switch alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        value.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
    }

    private func applyList(
        _ listStyle: RichTextListStyle,
        in range: NSRange,
        value: NSMutableAttributedString
    ) {
        let paragraphRange = (value.string as NSString).paragraphRange(for: range)
        guard paragraphRange.length > 0 else { return }
        let style = mutableParagraphStyle(at: paragraphRange.location, in: value)
        let markerFormat: NSTextList.MarkerFormat = switch listStyle {
        case .bulleted: .disc
        case .numbered: .decimal
        }
        style.textLists = [NSTextList(markerFormat: markerFormat, options: 0)]
        value.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
    }

    private func mutableParagraphStyle(
        at location: Int,
        in value: NSAttributedString
    ) -> NSMutableParagraphStyle {
        if let existing = value.attribute(
            .paragraphStyle,
            at: location,
            effectiveRange: nil
        ) as? NSParagraphStyle,
           let mutable = existing.mutableCopy() as? NSMutableParagraphStyle {
            return mutable
        }
        return NSMutableParagraphStyle()
    }

    private func togglingChecklist(
        in document: RichTextDocument,
        canonicalValue: NSAttributedString,
        selection: RichTextSelection
    ) throws -> RichTextDocument {
        guard canonicalValue.length > 0 else { return document }
        let location = min(selection.locationUTF16, canonicalValue.length - 1)
        guard let rawID = canonicalValue.attribute(
                  RichTextRuntimeAttributes.blockID,
                  at: location,
                  effectiveRange: nil
              ) as? String,
              let id = UUID(uuidString: rawID)
        else {
            return document
        }
        return try checklistMutation.togglingItem(id: id, in: document)
    }
}
