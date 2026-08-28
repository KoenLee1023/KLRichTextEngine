# 시작하기

KLRichTextEngine은 구조화된 리치 텍스트의 편집, 표시, 검증을 위한 Swift 패키지입니다. 문서 의미와 직렬화는 패키지가 담당하고, 저장과 화면 전환 및 플랫폼 연동은 호스트 앱이 담당합니다.

Swift Package Manager로 추가한 뒤 `KLRichTextEngine`을 import하세요. 편집에는 `RichTextEditor`, 표시에는 `RichTextViewer`, JSON 입출력에는 `RichTextDocumentCodec`을 사용합니다.

iOS 17 이상과 macOS 14 이상을 지원합니다. `RichTextSwiftUIEditor`는 iOS 26 이상에서 사용할 수 있습니다.
