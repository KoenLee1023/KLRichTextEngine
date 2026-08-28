#if os(iOS)
import SwiftUI

@MainActor
struct RichTextKeyboardToolbar: ToolbarContent {
    let isChecklistEnabled: Bool
    let perform: (RichTextFormattingCommand) -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.bold"), systemImage: "bold") {
                perform(.bold)
            }
            Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.italic"), systemImage: "italic") {
                perform(.italic)
            }
            Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.underline"), systemImage: "underline") {
                perform(.underline)
            }
            Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.strikethrough"), systemImage: "strikethrough") {
                perform(.strikethrough)
            }
            Menu(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.more"), systemImage: "ellipsis.circle") {
                Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.body")) {
                    perform(.textStyle(.body))
                }
                Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.title")) {
                    perform(.textStyle(.title))
                }
                Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.heading")) {
                    perform(.textStyle(.heading))
                }
                Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.bulleted_list")) {
                    perform(.list(.bulleted))
                }
                Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.numbered_list")) {
                    perform(.list(.numbered))
                }
                Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.clear_formatting")) {
                    perform(.clear)
                }
                if isChecklistEnabled {
                    Button(RichTextPackageLocalization.string(forKey: "rich_text.toolbar.checklist"), systemImage: "checklist") {
                        perform(.toggleChecklist)
                    }
                }
            }
        }
    }
}

struct RichTextEditorCommandRequest: Equatable {
    let sequence: Int
    let command: RichTextFormattingCommand
}
#endif
