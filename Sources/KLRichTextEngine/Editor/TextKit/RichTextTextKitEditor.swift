#if os(iOS)
import SwiftUI
import UIKit

@MainActor
struct RichTextTextKitEditor: View {
    @Binding var document: RichTextDocument
    let access: RichTextDocumentAccess
    let configuration: RichTextEditorConfiguration
    let theme: RichTextTheme

    @State private var commandSequence = 0
    @State private var commandRequest: RichTextEditorCommandRequest?

    var body: some View {
        RichTextTextViewBridge(
            document: $document,
            access: access,
            configuration: configuration,
            theme: theme,
            commandRequest: commandRequest
        )
        .toolbar {
            if RichTextEditorCoordinatorState.shouldShowMutationToolbar(access: access) {
                RichTextKeyboardToolbar(
                    isChecklistEnabled: configuration.isChecklistEnabled,
                    perform: request
                )
            }
        }
    }

    private func request(_ command: RichTextFormattingCommand) {
        commandSequence += 1
        commandRequest = RichTextEditorCommandRequest(
            sequence: commandSequence,
            command: command
        )
    }
}

@MainActor
struct RichTextTextViewBridge: UIViewRepresentable {
    @Binding var document: RichTextDocument
    let access: RichTextDocumentAccess
    let configuration: RichTextEditorConfiguration
    let theme: RichTextTheme
    let commandRequest: RichTextEditorCommandRequest?

    func makeUIView(context: Context) -> RichTextTextView {
        let textView = RichTextTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.tintColor = UIColor(theme.accentColor)
        textView.textColor = UIColor(theme.defaultTextColor)
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = true
        textView.adjustsFontForContentSizeCategory = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.traitsDidChange = { [weak coordinator = context.coordinator] in
            coordinator?.refreshForCurrentTraits()
        }
        context.coordinator.textView = textView
        context.coordinator.installInitialValue(in: textView)
        return textView
    }

    func updateUIView(_ textView: RichTextTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextTextViewBridge
        weak var textView: RichTextTextView?

        private var state: RichTextEditorCoordinatorState
        private var handledCommandSequence = 0
        private var lastSelectedRange = NSRange(location: 0, length: 0)
        private var isApplyingProgrammaticChange = false

        init(parent: RichTextTextViewBridge) {
            self.parent = parent
            state = RichTextEditorCoordinatorState(
                initialFocusRequest: parent.configuration.focusRequest
            )
        }

        func installInitialValue(in textView: RichTextTextView) {
            applyRenderedDocument(
                parent.document,
                selection: NSRange(location: 0, length: 0),
                contentOffset: .zero,
                in: textView
            )
            updateBehavior(textView)
        }

        func update(_ textView: RichTextTextView) {
            updateBehavior(textView)
            applyPendingCommand(in: textView)
            refreshExternalDocument(in: textView)
            if state.consumeFocusRequest(parent.configuration.focusRequest) {
                textView.becomeFirstResponder()
            }
        }

        func refreshForCurrentTraits() {
            guard let textView, textView.markedTextRange == nil else { return }
            applyRenderedDocument(
                parent.document,
                selection: textView.selectedRange,
                contentOffset: textView.contentOffset,
                in: textView
            )
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingProgrammaticChange,
                  textView.markedTextRange == nil,
                  parent.access == .editable
            else {
                return
            }
            do {
                let value = NSAttributedString(attributedString: textView.attributedText)
                let parsed = try RichTextEditorDependencies.codec.document(
                    from: value,
                    reconciling: parent.document
                )
                if parsed != parent.document {
                    parent.document = parsed
                }
            } catch {
                return
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let selection = textView.selectedRange.clamped(
                toUTF16Length: textView.textStorage.length
            )
            if selection.length > 0 {
                lastSelectedRange = selection
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.configuration.onFocusChange?(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.configuration.onFocusChange?(false)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            do {
                let route = try routeTextKitReplacement(
                    text,
                    replacing: range,
                    in: textView
                )
                switch route {
                case .passThrough:
                    return true
                case .reject:
                    return false
                case .handled:
                    return false
                }
            } catch {
                return false
            }
        }

        private func updateBehavior(_ textView: RichTextTextView) {
            let isEditable = parent.access == .editable
            textView.isEditable = isEditable
            textView.allowsEditingTextAttributes = isEditable
            textView.isScrollEnabled = parent.configuration.isScrollEnabled
            textView.showsVerticalScrollIndicator = parent.configuration.isScrollEnabled
            textView.tintColor = UIColor(parent.theme.accentColor)
            textView.textColor = UIColor(parent.theme.defaultTextColor)
            textView.invalidateIntrinsicContentSize()
        }

        private func applyPendingCommand(in textView: RichTextTextView) {
            guard let request = parent.commandRequest,
                  request.sequence != handledCommandSequence,
                  parent.access == .editable,
                  textView.markedTextRange == nil
            else {
                return
            }
            handledCommandSequence = request.sequence

            var value = NSAttributedString(attributedString: textView.attributedText)
            var document = parent.document
            var selection = richTextSelection(in: textView)
            do {
                try RichTextEditorDependencies.mutationEngine.apply(
                    request.command,
                    to: &value,
                    document: &document,
                    selection: &selection
                )
                applyMutation(
                    value: value,
                    document: document,
                    selection: selection,
                    in: textView
                )
            } catch {
                return
            }
        }

        private func routeTextKitReplacement(
            _ text: String,
            replacing range: NSRange,
            in textView: UITextView
        ) throws -> RichTextTextKitReplacementRoute {
            var value = NSAttributedString(attributedString: textView.attributedText)
            var document = parent.document
            var selection = richTextSelection(in: textView)
            let route = try RichTextEditorCoordinatorState.routeTextKitReplacement(
                text,
                replacing: range,
                access: parent.access,
                hasMarkedText: textView.markedTextRange != nil,
                to: &value,
                document: &document,
                selection: &selection,
                mutationEngine: RichTextEditorDependencies.mutationEngine
            )
            if route == .handled {
                applyMutation(
                    value: value,
                    document: document,
                    selection: selection,
                    in: textView
                )
            }
            return route
        }

        private func applyMutation(
            value: NSAttributedString,
            document: RichTextDocument,
            selection: RichTextSelection,
            in textView: UITextView
        ) {
            let previousDocument = parent.document
            let previousSelection = textView.selectedRange
            textView.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.restore(
                    document: previousDocument,
                    selection: previousSelection
                )
            }
            parent.document = document
            setAttributedValue(
                value,
                selection: NSRange(
                    location: selection.locationUTF16,
                    length: selection.lengthUTF16
                ),
                contentOffset: textView.contentOffset,
                in: textView
            )
        }

        private func restore(document: RichTextDocument, selection: NSRange) {
            guard let textView else { return }
            let redoDocument = parent.document
            let redoSelection = textView.selectedRange
            textView.undoManager?.registerUndo(withTarget: self) { coordinator in
                coordinator.restore(document: redoDocument, selection: redoSelection)
            }
            parent.document = document
            applyRenderedDocument(
                document,
                selection: selection,
                contentOffset: textView.contentOffset,
                in: textView
            )
        }

        private func refreshExternalDocument(in textView: UITextView) {
            guard let expected = try? RichTextEditorDependencies.codec.attributedString(
                from: parent.document,
                traits: textView.traitCollection
            ),
            RichTextEditorCoordinatorState.shouldApplyExternalValue(
                current: textView.attributedText,
                expected: expected,
                hasMarkedText: textView.markedTextRange != nil
            ) else {
                return
            }
            setAttributedValue(
                expected,
                selection: textView.selectedRange,
                contentOffset: textView.contentOffset,
                in: textView
            )
        }

        private func applyRenderedDocument(
            _ document: RichTextDocument,
            selection: NSRange,
            contentOffset: CGPoint,
            in textView: UITextView
        ) {
            guard let value = try? RichTextEditorDependencies.codec.attributedString(
                from: document,
                traits: textView.traitCollection
            ) else {
                return
            }
            setAttributedValue(
                value,
                selection: selection,
                contentOffset: contentOffset,
                in: textView
            )
        }

        private func setAttributedValue(
            _ value: NSAttributedString,
            selection: NSRange,
            contentOffset: CGPoint,
            in textView: UITextView
        ) {
            let typingAttributes = textView.typingAttributes
            isApplyingProgrammaticChange = true
            textView.undoManager?.disableUndoRegistration()
            textView.textStorage.beginEditing()
            textView.textStorage.setAttributedString(value)
            textView.textStorage.endEditing()
            textView.undoManager?.enableUndoRegistration()
            textView.selectedRange = selection.clamped(toUTF16Length: value.length)
            textView.typingAttributes = typingAttributes
            textView.setContentOffset(contentOffset, animated: false)
            textView.invalidateIntrinsicContentSize()
            isApplyingProgrammaticChange = false
        }

        private func richTextSelection(in textView: UITextView) -> RichTextSelection {
            let current = textView.selectedRange.clamped(
                toUTF16Length: textView.textStorage.length
            )
            let selected = current.length > 0
                ? current
                : lastSelectedRange.clamped(toUTF16Length: textView.textStorage.length)
            return RichTextSelection(
                locationUTF16: selected.location,
                lengthUTF16: selected.length
            )
        }
    }
}
#endif
