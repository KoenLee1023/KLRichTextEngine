import Foundation

enum RichTextRuntimeAttributes {
    static let zeroLengthSentinel = "\u{2060}"

    static let blockID = NSAttributedString.Key(
        "dev.nuancery-labs.KLRichTextEngine.runtime.block-id"
    )
    static let blockKind = NSAttributedString.Key(
        "dev.nuancery-labs.KLRichTextEngine.runtime.block-kind"
    )
    static let checklistIsChecked = NSAttributedString.Key(
        "dev.nuancery-labs.KLRichTextEngine.runtime.checklist-is-checked"
    )
    static let checklistCompletionDecoration = NSAttributedString.Key(
        "dev.nuancery-labs.KLRichTextEngine.runtime.checklist-completion-decoration"
    )
    static let authoredStrikethroughStyle = NSAttributedString.Key(
        "dev.nuancery-labs.KLRichTextEngine.runtime.authored-strikethrough-style"
    )
    static let followingEmptyBlockSnapshot = NSAttributedString.Key(
        "dev.nuancery-labs.KLRichTextEngine.runtime.following-empty-block-snapshot"
    )
    static let documentProvenance = NSAttributedString.Key(
        "dev.nuancery-labs.KLRichTextEngine.runtime.document-provenance"
    )
    static let fontIntent = NSAttributedString.Key(
        "dev.nuancery-labs.KLRichTextEngine.runtime.font-intent"
    )

    static let all: [NSAttributedString.Key] = [
        blockID,
        blockKind,
        checklistIsChecked,
        checklistCompletionDecoration,
        authoredStrikethroughStyle,
        followingEmptyBlockSnapshot,
        documentProvenance,
        fontIntent,
    ]
}
