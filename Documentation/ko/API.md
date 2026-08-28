# API

`KLRichTextEngine`은 구조화된 문서 모델, 코덱, 편집 명령, SwiftUI 편집기와 뷰어를 제공합니다. `RichTextDocument`가 저장되는 기준 데이터이며 attributed string과 플랫폼 텍스트 뷰는 표현 계층입니다.

`RichTextDocument`는 순서가 있는 `RichTextBlock`을 담습니다. `RichTextParagraph`는 속성 콘텐츠를, `RichTextChecklistItem`은 체크 상태를, `RichTextContent`는 콘텐츠와 글꼴 저장 방식을 보존합니다. `RichTextDocumentCodec`은 `RichTextJSONEncodingVersion`에 따라 JSON을 읽고 씁니다.

`RichTextDocumentAccess`와 `RichTextDocumentLoadResult`는 편집 가능, 읽기 전용, 호환성 제한 상태를 구분합니다. `RichTextMutationEngine`은 `RichTextFormattingCommand`를 `RichTextSelection`에 적용합니다. `RichTextChecklistMutation`은 타입이 지정된 오류를 반환하고 `RichTextPlainPastePolicy`는 일반 텍스트 입력 방식을 정합니다.

`RichTextEditor`와 `RichTextViewer`는 편집 및 표시 설정을 사용합니다. 영속화, 실행 취소 기록, 제목, 네트워크, 앱 명령은 호스트가 관리합니다.

