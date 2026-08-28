# 开始使用

KLRichTextEngine 是用于编辑、渲染和校验结构化富文本的 Swift 软件包。软件包负责文档语义和序列化。宿主应用负责存储、导航和平台接入。

通过 Swift Package Manager 添加软件包，然后导入 `KLRichTextEngine`。

```swift
let codec = RichTextDocumentCodec()
let data = try codec.encodeJSON(document, version: .v1)
let loaded = try codec.decodeJSON(data)
```

可用 `RichTextEditor` 构建可编辑的 iOS 界面，用 `RichTextViewer` 展示只读或紧凑内容。请把 `RichTextDocument` 作为唯一数据来源，具体保存 JSON 还是 RTF 由宿主决定。

软件包支持 iOS 17 及更高版本、macOS 14 及更高版本。`RichTextSwiftUIEditor` 仅在 iOS 26 及更高版本提供。
