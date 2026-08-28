#if os(iOS)
import SwiftUI

@MainActor
/// A SwiftUI editor backed by a ``RichTextDocument`` binding.
public struct RichTextEditor: View {
    @Binding private var document: RichTextDocument
    private let access: RichTextDocumentAccess
    private let configuration: RichTextEditorConfiguration
    private let theme: RichTextTheme

    public init(
        document: Binding<RichTextDocument>,
        access: RichTextDocumentAccess,
        configuration: RichTextEditorConfiguration,
        theme: RichTextTheme
    ) {
        _document = document
        self.access = access
        self.configuration = configuration
        self.theme = theme
    }

    public var body: some View {
        switch RichTextEditorRouting.resolve(
            configuration.backend,
            capability: RichTextEditorSystemVersionCapability()
        ) {
        case .swiftUI:
            if #available(iOS 26.0, *) {
                RichTextSwiftUIEditor(
                    document: $document,
                    access: access,
                    configuration: configuration,
                    theme: theme
                )
            } else {
                compatibilityEditor
            }
        case .textKitCompatibility:
            compatibilityEditor
        }
    }

    private var compatibilityEditor: some View {
        RichTextTextKitEditor(
            document: $document,
            access: access,
            configuration: configuration,
            theme: theme
        )
    }
}

enum RichTextEditorDependencies {
    static let codec = RichTextDocumentCodec(
        validationPolicy: RichTextDocumentValidationPolicy(
            maximumBlockCount: 100_000,
            maximumTextUTF8Bytes: 256 * 1_024 * 1_024,
            maximumEmbeddedDataBytes: 512 * 1_024 * 1_024
        )
    )

    static let mutationEngine = RichTextMutationEngine(documentCodec: codec)
}
#endif
