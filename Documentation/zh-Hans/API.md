# API

`KLRichTextEngine` 提供结构化文档模型、编解码器、编辑命令，以及 SwiftUI 编辑器和查看器。`RichTextDocument` 是持久化的唯一数据来源，富文本字符串和平台文本视图只是展示投影。

`RichTextDocument` 包含有序的`RichTextBlock`。`RichTextParagraph`保存带属性内容，`RichTextChecklistItem`保存清单状态，`RichTextContent`定义内容和字体存储方式。`RichTextDocumentCodec`根据`RichTextJSONEncodingVersion`读写 JSON 格式。

`RichTextDocumentAccess`和`RichTextDocumentLoadResult`区分可编辑、只读和受兼容性限制的状态。`RichTextMutationEngine`把`RichTextFormattingCommand`应用到`RichTextSelection`。`RichTextChecklistMutation`修改清单并返回明确错误，`RichTextPlainPastePolicy`定义纯文本粘贴方式。

`RichTextEditor`使用`RichTextEditorConfiguration`和`RichTextEditorBackend`编辑。`RichTextViewer`使用`RichTextViewerRenderingPolicy`和`RichTextViewerAppearance`展示只读内容。持久化、撤销历史、标题、网络和应用命令由宿主负责。

