#if os(iOS)
import SwiftUI
import UIKit

@available(iOS 26.0, *)
@MainActor
struct RichTextSwiftUIEditor: View {
    @Binding private var document: RichTextDocument
    private let access: RichTextDocumentAccess
    private let configuration: RichTextEditorConfiguration
    private let theme: RichTextTheme

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.undoManager) private var undoManager
    @FocusState private var isFocused: Bool
    @State private var text: AttributedString
    @State private var selection: AttributedTextSelection
    @State private var coordinatorState: RichTextEditorCoordinatorState
    @State private var isApplyingExternalValue = false
    @State private var undoTarget = RichTextSwiftUIUndoTarget()

    init(
        document: Binding<RichTextDocument>,
        access: RichTextDocumentAccess,
        configuration: RichTextEditorConfiguration,
        theme: RichTextTheme
    ) {
        _document = document
        self.access = access
        self.configuration = configuration
        self.theme = theme
        let initialValue = (try? RichTextEditorDependencies.codec.attributedString(
            from: document.wrappedValue
        )) ?? NSAttributedString(string: document.wrappedValue.plainText)
        _text = State(initialValue: AttributedString(initialValue))
        _selection = State(initialValue: AttributedTextSelection())
        _coordinatorState = State(initialValue: RichTextEditorCoordinatorState(
            initialFocusRequest: configuration.focusRequest
        ))
    }

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .focused($isFocused)
            .disabled(access != .editable)
            .scrollDisabled(!configuration.isScrollEnabled)
            .tint(theme.accentColor)
            .toolbar {
                if RichTextEditorCoordinatorState.shouldShowMutationToolbar(access: access) {
                    RichTextKeyboardToolbar(
                        isChecklistEnabled: configuration.isChecklistEnabled,
                        perform: apply
                    )
                }
            }
            .onAppear {
                undoTarget.restore = restore
                refreshFromDocument()
            }
            .onDisappear {
                undoTarget.restore = nil
            }
            .onChange(of: text) {
                publishTextChange()
            }
            .onChange(of: document) {
                if coordinatorState.shouldRefreshForDocumentChange(document) {
                    refreshFromDocument()
                }
            }
            .onChange(of: dynamicTypeSize) {
                refreshFromDocument()
            }
            .onChange(of: colorScheme) {
                refreshFromDocument()
            }
            .onChange(of: configuration.focusRequest) {
                consumeFocusRequest()
            }
            .onChange(of: isFocused) { _, newValue in
                configuration.onFocusChange?(newValue)
            }
    }

    private func apply(_ command: RichTextFormattingCommand) {
        guard access == .editable else { return }
        var nextText = text
        var nextDocument = document
        var nextSelection = richTextSelection()
        let snapshot = currentSnapshot()
        do {
            try RichTextEditorDependencies.mutationEngine.apply(
                command,
                to: &nextText,
                document: &nextDocument,
                selection: &nextSelection
            )
        } catch {
            return
        }
        registerUndo(snapshot)
        isApplyingExternalValue = true
        text = nextText
        document = nextDocument
        selection = attributedSelection(for: nextSelection, in: nextText)
        isApplyingExternalValue = false
        isFocused = true
    }

    private func publishTextChange() {
        guard !isApplyingExternalValue, access == .editable else { return }
        do {
            if try applyChecklistReturnIfNeeded() {
                return
            }
            let parsed = try RichTextEditorDependencies.codec.document(
                from: NSAttributedString(text),
                reconciling: document
            )
            if parsed != document {
                coordinatorState.recordPublishedDocument(parsed)
                document = parsed
            }
        } catch {
            refreshFromDocument()
        }
    }

    private func applyChecklistReturnIfNeeded() throws -> Bool {
        let currentValue = NSAttributedString(text)
        let previousValue = try RichTextEditorDependencies.codec.attributedString(
            from: document,
            traits: traitCollection
        )
        guard let returnSelection = RichTextEditorCoordinatorState
            .singleInsertedNewlineSelection(
                previous: previousValue.string,
                updated: currentValue.string
            )
        else {
            return false
        }

        var nextText = AttributedString(previousValue)
        var nextDocument = document
        var nextSelection = returnSelection
        let snapshot = currentSnapshot()
        try RichTextEditorDependencies.mutationEngine.pastePlainText(
            "\n",
            into: &nextText,
            document: &nextDocument,
            selection: &nextSelection
        )
        registerUndo(snapshot)
        isApplyingExternalValue = true
        text = nextText
        document = nextDocument
        selection = attributedSelection(for: nextSelection, in: nextText)
        isApplyingExternalValue = false
        return true
    }

    private func refreshFromDocument() {
        let selectedRange = richTextSelection()
        guard let rendered = try? RichTextEditorDependencies.codec.attributedString(
            from: document,
            traits: traitCollection
        ) else {
            return
        }
        let expected = AttributedString(rendered)
        guard NSAttributedString(text).isEqual(to: rendered) == false else { return }
        isApplyingExternalValue = true
        text = expected
        selection = attributedSelection(for: selectedRange, in: expected)
        isApplyingExternalValue = false
    }

    private func consumeFocusRequest() {
        guard coordinatorState.consumeFocusRequest(configuration.focusRequest) else {
            return
        }
        isFocused = true
    }

    private func richTextSelection() -> RichTextSelection {
        switch selection.indices(in: text) {
        case let .insertionPoint(index):
            let range = NSRange(index..<index, in: text)
            return RichTextSelection(locationUTF16: range.location, lengthUTF16: 0)
        case let .ranges(ranges):
            guard let first = ranges.ranges.first,
                  let last = ranges.ranges.last
            else {
                return RichTextSelection(locationUTF16: 0, lengthUTF16: 0)
            }
            let range = NSRange(first.lowerBound..<last.upperBound, in: text)
            return RichTextSelection(
                locationUTF16: range.location,
                lengthUTF16: range.length
            )
        }
    }

    private func attributedSelection(
        for selection: RichTextSelection,
        in value: AttributedString
    ) -> AttributedTextSelection {
        let range = NSRange(
            location: selection.locationUTF16,
            length: selection.lengthUTF16
        )
        guard let attributedRange = Range<AttributedString.Index>(range, in: value) else {
            return AttributedTextSelection(insertionPoint: value.endIndex)
        }
        if attributedRange.isEmpty {
            return AttributedTextSelection(insertionPoint: attributedRange.lowerBound)
        }
        return AttributedTextSelection(range: attributedRange)
    }

    private var traitCollection: UITraitCollection {
        UITraitCollection { traits in
            traits[UITraitPreferredContentSizeCategory.self] = contentSizeCategory
            traits[UITraitUserInterfaceStyle.self] = colorScheme == .dark ? .dark : .light
        }
    }

    private var contentSizeCategory: UIContentSizeCategory {
        switch dynamicTypeSize {
        case .xSmall:
            .extraSmall
        case .small:
            .small
        case .medium:
            .medium
        case .large:
            .large
        case .xLarge:
            .extraLarge
        case .xxLarge:
            .extraExtraLarge
        case .xxxLarge:
            .extraExtraExtraLarge
        case .accessibility1:
            .accessibilityMedium
        case .accessibility2:
            .accessibilityLarge
        case .accessibility3:
            .accessibilityExtraLarge
        case .accessibility4:
            .accessibilityExtraExtraLarge
        case .accessibility5:
            .accessibilityExtraExtraExtraLarge
        @unknown default:
            .large
        }
    }

    private func currentSnapshot() -> RichTextSwiftUIEditorSnapshot {
        RichTextSwiftUIEditorSnapshot(
            document: document,
            text: text,
            selection: selection
        )
    }

    private func registerUndo(_ snapshot: RichTextSwiftUIEditorSnapshot) {
        undoManager?.registerUndo(withTarget: undoTarget) { target in
            target.restore?(snapshot)
        }
    }

    private func restore(_ snapshot: RichTextSwiftUIEditorSnapshot) {
        registerUndo(currentSnapshot())
        isApplyingExternalValue = true
        document = snapshot.document
        text = snapshot.text
        selection = snapshot.selection
        isApplyingExternalValue = false
    }
}

@available(iOS 26.0, *)
private struct RichTextSwiftUIEditorSnapshot {
    let document: RichTextDocument
    let text: AttributedString
    let selection: AttributedTextSelection
}

@available(iOS 26.0, *)
@MainActor
private final class RichTextSwiftUIUndoTarget: NSObject {
    var restore: ((RichTextSwiftUIEditorSnapshot) -> Void)?
}
#endif
