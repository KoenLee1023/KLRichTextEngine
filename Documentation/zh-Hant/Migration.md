# 從應用程式內部實作遷移

保留現有持久化層與業務 ID，在編輯器邊界改用 `RichTextDocument`，再用 `RichTextDocumentCodec` 讀取舊 JSON 或 RTF。解碼後先檢查 `RichTextDocumentLoadResult.access`，確認可編輯後再啟用編輯。

不要將執行時富文字屬性寫入持久化資料，也不要在遷移時重建區塊 ID。未知格式及不支援的字型模式應保持唯讀，直到宿主提供明確的轉換流程。
