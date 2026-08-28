import Foundation

/// A formatting operation accepted by ``RichTextMutationEngine``.
public enum RichTextFormattingCommand: Equatable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough
    case clear
    case alignment(RichTextAlignment)
    case list(RichTextListStyle)
    case textStyle(RichTextTextStyle)
    case toggleChecklist
}

public enum RichTextAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

public enum RichTextListStyle: Equatable, Sendable {
    case bulleted
    case numbered
}

public enum RichTextTextStyle: Equatable, Sendable {
    case body
    case title
    case heading
    case subheading
    case footnote
    case fixedPointSize(Double)
}

extension RichTextFormattingCommand {
    var appliesToParagraph: Bool {
        switch self {
        case .alignment, .list:
            true
        case .bold, .italic, .underline, .strikethrough, .clear, .textStyle,
             .toggleChecklist:
            false
        }
    }
}

extension RichTextTextStyle {
    var fontIntent: RichTextFontIntent {
        get throws {
            switch self {
            case .body:
                .dynamicBody
            case .title:
                .dynamicTextStyle(.title)
            case .heading:
                .dynamicTextStyle(.heading)
            case .subheading:
                .dynamicTextStyle(.subheading)
            case .footnote:
                .dynamicTextStyle(.footnote)
            case let .fixedPointSize(pointSize):
                if pointSize.isFinite, pointSize > 0 {
                    .fixedPointSize(pointSize)
                } else {
                    throw RichTextDocumentCodecError.validationFailure
                }
            }
        }
    }
}

struct RichTextMutationOutput {
    let value: NSAttributedString
    let document: RichTextDocument
    let selection: RichTextSelection
}

enum RichTextMutationFontTrait {
    case bold
    case italic
}
