# 開始使用

KLRichTextEngine 是用於編輯、呈現及驗證結構化富文字的 Swift 套件。套件負責文件語意與序列化，宿主應用程式負責儲存、導覽及平台整合。

使用 Swift Package Manager 加入套件，然後匯入 `KLRichTextEngine`。以 `RichTextDocumentCodec` 編碼或載入 JSON，以 `RichTextEditor` 編輯，以 `RichTextViewer` 顯示唯讀內容。

套件支援 iOS 17 以上及 macOS 14 以上。`RichTextSwiftUIEditor` 僅在 iOS 26 以上提供。
