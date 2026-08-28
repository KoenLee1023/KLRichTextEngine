# 示例

仓库包含三个独立的 iOS demo，它们都通过 Swift Package Manager 使用本地软件包。

- `Examples/Composer` 使用 `RichTextEditor` 编辑文档，并用 `RichTextDocumentCodec` 导出版本化 JSON。
- `Examples/InteractiveReader` 使用 `RichTextViewer` 展示可选择内容，通过 `RichTextChecklistMutation` 切换清单。
- `Examples/MigrationLab` 加载正常、未知和损坏的输入，展示相应的访问状态。

示例使用合成数据，只用于说明软件包边界，不代表生产数据。
