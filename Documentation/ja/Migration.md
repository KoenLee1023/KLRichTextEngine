# アプリ内実装からの移行

既存の保存層と業務 ID は維持し、エディターとの境界で `RichTextDocument` を使います。旧 JSON または RTF は `RichTextDocumentCodec` で読み込み、`RichTextDocumentLoadResult.access` を確認してから編集を有効にします。

実行時の属性を保存データへコピーしたり、移行時にブロック ID を作り直したりしないでください。未知の形式は、明確な変換処理を用意するまで読み取り専用で扱います。
