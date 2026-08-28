#if canImport(UIKit)
import SwiftUI
import UIKit
@testable import KLRichTextEngine

@MainActor
func requireLockedAttributedStringAPI(
    codec: RichTextDocumentCodec,
    document: RichTextDocument,
    traits: UITraitCollection
) throws -> NSAttributedString {
    try codec.attributedString(from: document, traits: traits)
}

@MainActor
func requireLockedDocumentAPI(
    codec: RichTextDocumentCodec,
    value: NSAttributedString,
    previous: RichTextDocument?
) throws -> RichTextDocument {
    try codec.document(from: value, reconciling: previous)
}

func requireNewEditableAttributedStringAPI(
    codec: RichTextDocumentCodec,
    value: NSAttributedString
) throws -> NSAttributedString {
    try codec.editableAttributedString(from: value)
}

@MainActor
func requireRichTextEditorPublicContract(
    document: Binding<RichTextDocument>,
    access: RichTextDocumentAccess,
    onFocusChange: @escaping (Bool) -> Void
) -> some View {
    var configuration = RichTextEditorConfiguration(
        backend: .automatic,
        isChecklistEnabled: true,
        isScrollEnabled: false,
        focusRequest: 3,
        onFocusChange: onFocusChange
    )
    configuration.backend = .textKitCompatibility
    configuration.isChecklistEnabled = false
    configuration.isScrollEnabled = true
    configuration.focusRequest = 4
    configuration.onFocusChange = onFocusChange

    var theme = RichTextTheme(
        accentColor: .blue,
        checkedColor: .secondary,
        defaultTextColor: .primary
    )
    theme.accentColor = .green
    theme.checkedColor = .gray
    theme.defaultTextColor = .black

    return RichTextEditor(
        document: document,
        access: access,
        configuration: configuration,
        theme: theme
    )
}

@MainActor
func requireBothEditorAvailabilityBranches(
    document: Binding<RichTextDocument>,
    theme: RichTextTheme
) -> some View {
    Group {
        if #available(iOS 26.0, *) {
            RichTextEditor(
                document: document,
                access: .editable,
                configuration: RichTextEditorConfiguration(backend: .swiftUI),
                theme: theme
            )
        } else {
            RichTextEditor(
                document: document,
                access: .editable,
                configuration: RichTextEditorConfiguration(
                    backend: .textKitCompatibility
                ),
                theme: theme
            )
        }
    }
}

@MainActor
func requireEditorBackendLifecycleCompilation(
    document: Binding<RichTextDocument>,
    theme: RichTextTheme
) {
    let configuration = RichTextEditorConfiguration(
        backend: .textKitCompatibility,
        isChecklistEnabled: true,
        isScrollEnabled: true,
        focusRequest: 1
    )
    let controller = UIHostingController(
        rootView: RichTextEditor(
            document: document,
            access: .editable,
            configuration: configuration,
            theme: theme
        )
    )
    _ = controller.view

    if #available(iOS 26.0, *) {
        let nativeController = UIHostingController(
            rootView: RichTextEditor(
                document: document,
                access: .editable,
                configuration: RichTextEditorConfiguration(backend: .swiftUI),
                theme: theme
            )
        )
        _ = nativeController.view
    }
}

@MainActor
func requireTextKitDelegateEntryCompilation(
    document: Binding<RichTextDocument>,
    theme: RichTextTheme
) {
    let bridge = RichTextTextViewBridge(
        document: document,
        access: .editable,
        configuration: RichTextEditorConfiguration(),
        theme: theme,
        commandRequest: nil
    )
    let delegate: UITextViewDelegate = bridge.makeCoordinator()
    let textView = RichTextTextView()

    _ = delegate.textView?(
        textView,
        shouldChangeTextIn: NSRange(location: 0, length: 0),
        replacementText: "\n"
    )
}
#endif
