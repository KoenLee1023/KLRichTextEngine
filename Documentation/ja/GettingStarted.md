# はじめに

KLRichTextEngine は、構造化されたリッチテキストの編集、表示、検証を行う Swift パッケージです。ドキュメントの意味とシリアライズを担当し、保存、画面遷移、プラットフォーム連携はホストアプリが担当します。

Swift Package Manager で追加して `KLRichTextEngine` を import してください。編集には `RichTextEditor`、表示には `RichTextViewer`、JSON の入出力には `RichTextDocumentCodec` を使用します。

iOS 17 以降、macOS 14 以降に対応します。`RichTextSwiftUIEditor` は iOS 26 以降で利用できます。
