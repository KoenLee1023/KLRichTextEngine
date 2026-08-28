# API

`KLRichTextEngine` 提供結構化文件模型、編解碼器、編輯命令，以及 SwiftUI 編輯器與檢視器。`RichTextDocument` 是持久化的唯一資料來源，富文字字串與平台文字視圖只是展示投影。

`RichTextDocument` 包含有序的`RichTextBlock`。`RichTextParagraph`保存帶屬性的內容，`RichTextChecklistItem`保存清單狀態，`RichTextContent`定義內容與字型儲存方式。`RichTextDocumentCodec`依`RichTextJSONEncodingVersion`讀寫 JSON 格式。

`RichTextDocumentAccess`與`RichTextDocumentLoadResult`區分可編輯、唯讀與受相容性限制的狀態。`RichTextMutationEngine`將`RichTextFormattingCommand`套用到`RichTextSelection`。`RichTextChecklistMutation`修改清單並回傳明確錯誤，`RichTextPlainPastePolicy`定義純文字貼上方式。

`RichTextEditor`使用`RichTextEditorConfiguration`與`RichTextEditorBackend`編輯。`RichTextViewer`使用`RichTextViewerRenderingPolicy`與`RichTextViewerAppearance`展示唯讀內容。持久化、復原歷史、標題、網路與應用程式命令由宿主負責。

