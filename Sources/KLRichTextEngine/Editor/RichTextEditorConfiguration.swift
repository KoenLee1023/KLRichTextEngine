import Foundation

protocol RichTextEditorVersionCapability: Sendable {
    var supportsSwiftUIRichTextEditor: Bool { get }
}

enum RichTextEditorResolvedBackend: Equatable, Sendable {
    case swiftUI
    case textKitCompatibility
}

enum RichTextTextKitReplacementRoute: Equatable {
    case passThrough
    case reject
    case handled
}

enum RichTextEditorRouting {
    static func automatic(
        capability: some RichTextEditorVersionCapability
    ) -> RichTextEditorResolvedBackend {
        capability.supportsSwiftUIRichTextEditor ? .swiftUI : .textKitCompatibility
    }

#if os(iOS)
    static func resolve(
        _ backend: RichTextEditorBackend,
        capability: some RichTextEditorVersionCapability
    ) -> RichTextEditorResolvedBackend {
        switch backend {
        case .automatic:
            automatic(capability: capability)
        case .swiftUI:
            capability.supportsSwiftUIRichTextEditor
                ? .swiftUI
                : .textKitCompatibility
        case .textKitCompatibility:
            .textKitCompatibility
        }
    }
#endif
}

struct RichTextEditorCoordinatorState {
    private var handledFocusRequest: Int
    private var lastPublishedDocument: RichTextDocument?

    init(initialFocusRequest: Int) {
        handledFocusRequest = initialFocusRequest
    }

    mutating func consumeFocusRequest(_ request: Int) -> Bool {
        guard request != handledFocusRequest else { return false }
        handledFocusRequest = request
        return true
    }

    mutating func recordPublishedDocument(_ document: RichTextDocument) {
        lastPublishedDocument = document
    }

    mutating func shouldRefreshForDocumentChange(
        _ document: RichTextDocument
    ) -> Bool {
        guard lastPublishedDocument == document else {
            lastPublishedDocument = nil
            return true
        }
        lastPublishedDocument = nil
        return false
    }

    static func shouldShowMutationToolbar(
        access: RichTextDocumentAccess
    ) -> Bool {
        access == .editable
    }

    static func shouldApplyExternalValue(
        current: NSAttributedString,
        expected: NSAttributedString,
        hasMarkedText: Bool
    ) -> Bool {
        !hasMarkedText && !current.isEqual(to: expected)
    }

    @MainActor
    static func routeTextKitReplacement(
        _ text: String,
        replacing range: NSRange,
        access: RichTextDocumentAccess,
        hasMarkedText: Bool,
        to value: inout NSAttributedString,
        document: inout RichTextDocument,
        selection: inout RichTextSelection,
        mutationEngine: RichTextMutationEngine
    ) throws -> RichTextTextKitReplacementRoute {
        guard access == .editable else { return .reject }
        guard !hasMarkedText, text == "\n" else { return .passThrough }

        var replacementSelection = RichTextSelection(
            locationUTF16: range.location,
            lengthUTF16: range.length
        )
        try mutationEngine.pastePlainText(
            text,
            into: &value,
            document: &document,
            selection: &replacementSelection
        )
        selection = replacementSelection
        return .handled
    }

    static func singleInsertedNewlineSelection(
        previous: String,
        updated: String
    ) -> RichTextSelection? {
        let previousValue = previous as NSString
        let updatedValue = updated as NSString
        guard updatedValue.length == previousValue.length + 1 else {
            return nil
        }

        var location = 0
        while location < previousValue.length,
              previousValue.character(at: location) == updatedValue.character(at: location)
        {
            location += 1
        }
        guard updatedValue.character(at: location) == 0x000A,
              previousValue.substring(from: location)
                == updatedValue.substring(from: location + 1)
        else {
            return nil
        }
        return RichTextSelection(locationUTF16: location, lengthUTF16: 0)
    }
}

#if os(iOS)
/// The platform text system used by ``RichTextEditor``.
public enum RichTextEditorBackend: Equatable, Sendable {
    case automatic
    case swiftUI
    case textKitCompatibility
}

/// Configuration for editor backend selection and input behavior.
public struct RichTextEditorConfiguration {
    public var backend: RichTextEditorBackend
    public var isChecklistEnabled: Bool
    public var isScrollEnabled: Bool
    public var focusRequest: Int
    public var onFocusChange: ((Bool) -> Void)?

    public init(
        backend: RichTextEditorBackend = .automatic,
        isChecklistEnabled: Bool = true,
        isScrollEnabled: Bool = true,
        focusRequest: Int = 0,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self.backend = backend
        self.isChecklistEnabled = isChecklistEnabled
        self.isScrollEnabled = isScrollEnabled
        self.focusRequest = focusRequest
        self.onFocusChange = onFocusChange
    }
}

struct RichTextEditorSystemVersionCapability: RichTextEditorVersionCapability {
    var supportsSwiftUIRichTextEditor: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
        }
    }
}
#endif
