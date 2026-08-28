# 앱 내부 구현에서 마이그레이션

기존 저장 계층과 업무 ID는 유지하고 편집기 경계에서 `RichTextDocument`를 사용합니다. 이전 JSON이나 RTF는 `RichTextDocumentCodec`으로 읽고 `RichTextDocumentLoadResult.access`를 확인한 뒤 편집을 허용하세요.

런타임 속성을 저장 데이터에 복사하거나 마이그레이션 중 블록 ID를 다시 만들지 마세요. 알 수 없는 형식은 명확한 변환 경로가 준비될 때까지 읽기 전용으로 처리합니다.
