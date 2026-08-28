# 从应用内实现迁移

保留应用现有的持久化层和业务 ID，在编辑器边界使用 `RichTextDocument`，再用 `RichTextDocumentCodec` 读取旧 JSON 或 RTF。

先用明确的 `RichTextDocumentValidationPolicy` 解码，检查 `RichTextDocumentLoadResult.access` 后再开启编辑。界面交给 `RichTextEditor` 或 `RichTextViewer`，变更通过 `RichTextMutationEngine` 或 `RichTextChecklistMutation` 完成。确认安全后再编码保存。

不要把运行时富文本属性写入持久化数据，也不要在迁移时重新生成区块 ID。未知格式和不支持的字体模式应保持只读，直到宿主提供明确的转换路径。
