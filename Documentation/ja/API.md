# API

`KLRichTextEngine` は構造化文書モデル、コーデック、編集コマンド、SwiftUI のエディタとビューアを提供します。`RichTextDocument` が保存する正本で、属性付き文字列やプラットフォームのテキストビューは投影です。

`RichTextDocument` は順序付きの`RichTextBlock`を持ちます。`RichTextParagraph`は属性付き内容、`RichTextChecklistItem`はチェック状態、`RichTextContent`は内容とフォント保存方式を保持します。`RichTextDocumentCodec`は`RichTextJSONEncodingVersion`に基づいて JSON を読み書きします。

`RichTextDocumentAccess`と`RichTextDocumentLoadResult`は編集可能、読み取り専用、互換性制限を区別します。`RichTextMutationEngine`は`RichTextFormattingCommand`を`RichTextSelection`に適用します。`RichTextChecklistMutation`は型付きエラーを返し、`RichTextPlainPastePolicy`はプレーンテキストの取り込み方を定めます。

`RichTextEditor`と`RichTextViewer`はそれぞれ設定、編集バックエンド、表示ポリシーを受け取ります。永続化、Undo 履歴、タイトル、ネットワーク、アプリ固有のコマンドはホストが管理します。

