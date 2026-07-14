# 편집 규칙 (rules)

이 폴더는 이 저장소를 **안전하게 고치기 위한 가드레일**을 주제별로 나눠 담는다. 대부분의
규칙은 어기면 "조용한 기동 실패"나 "손상된 백업" 같은, 즉시 드러나지 않는 사고로 이어진다.
결정의 배경은 [ADR](../adr/README.md)에, 코드 스타일은 [CONVENTIONS](../CONVENTIONS.md)에 있다.

> 대부분의 규칙은 `.\scripts\doctor.ps1`이 자동 점검한다. **편집 후 커밋 전 `.\scripts\check.ps1 -Test`를 돌린다.**

## 목록

| 파일 | 다루는 것 |
|------|-----------|
| [env-format.md](env-format.md) | `.env` 형식 — `$$` 이스케이프 · 슬래시 경로 · 인라인 주석 금지 |
| [instances.md](instances.md) | 인스턴스 추가/변경(3종 세트) · 선택 항목 양쪽 켜기 |
| [data-safety.md](data-safety.md) | 데이터 안전 — 바인드 마운트 · 엔진 백업 · 폴더 선생성 |
| [secrets.md](secrets.md) | SA 비밀번호 — 정책 · Git 제외 · `$$` 금지 |
| [images-restart.md](images-restart.md) | 이미지/sqlcmd 경로 · restart 변경 반영 |
| [authoring.md](authoring.md) | 새 스크립트 작성 · compose 직접 실행 |
| [workflow.md](workflow.md) | 작업 흐름 — worktree·PR·CI 게이트, 로드맵/버그는 GitHub 으로 추적 |
