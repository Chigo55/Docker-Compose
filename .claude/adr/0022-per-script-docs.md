---
summary: "스크립트 사용법을 docs/scripts/<name>.md 로 분리 — 요약의 단일 소스는 문서 frontmatter"
---

# ADR-0022: 스크립트 사용법을 스크립트당 파일로 분리한다 — 요약의 단일 소스는 문서 frontmatter

- 상태: Accepted
- 관련: [ADR-0021](0021-generated-doc-index.md)(같은 원칙을 ADR·rules 인덱스에 먼저 적용), [ADR-0020](0020-generate-release-notes-from-prs.md)(수기 집약 폐지), [ADR-0018](0018-wiki-for-learning-repo-for-code.md)(사용법은 저장소, 개념은 Wiki), [ADR-0007](0007-shared-common-library.md)(새 스크립트는 공용 라이브러리 재사용), 이슈 [#50](https://github.com/Chigo55/Docker-Compose/issues/50)·[#52](https://github.com/Chigo55/Docker-Compose/issues/52)

## 배경 (Context)

`docs/README.md` 는 #50 이 집계한 **최대 충돌 핫스팟**(변경 12회)이었다. 원인은 [ADR-0021](0021-generated-doc-index.md) 이
없앤 것과 **같은 구조**다 — `## 스크립트 사용법` 한 섹션에 스크립트당 `### <name>.ps1` 블록이 쌓이고,
스크립트를 추가하는 PR 마다 그 섹션 끝에 블록을 append 한다. 두 PR 이 병렬로 스크립트를 하나씩
추가하면 같은 자리에서 결정적으로 충돌한다.

폴더 구조 트리(`scripts/` 아래 스크립트를 한 줄씩 나열)도 같은 append 지점이었다.

한 줄 요약을 어디서 가져오느냐는 별도의 문제다. 스크립트에는 이미 comment-based help
`.SYNOPSIS` 가 있어(CONVENTIONS), 사용법 문서에도 요약을 두면 **한 줄이 두 곳에 사는** 이중
관리가 된다. 검토한 방식:

- **A. `.SYNOPSIS` 에서 요약을 뽑아 인덱스를 만든다.** 진짜 단일 소스가 된다. 그러나 `.SYNOPSIS` 는
  **셸에서 `Get-Help` 로 읽는 실행자용 한 줄**이고 인덱스는 **문서 독자용**이라 대상이 다르다.
  게다가 ADR·rules 는 frontmatter, scripts 만 `.SYNOPSIS` 로 규약이 갈려 생성기·검증이 두 갈래가 된다.
  채택 안 함.
- **B. 문서 frontmatter 와 `.SYNOPSIS` 의 문자열 일치를 CI 로 강제한다.** 드리프트는 막지만, 문체를
  조금만 다듬어도 CI 가 깨진다. 얻는 것에 비해 마찰이 크다. 채택 안 함.
- **C. 문서 frontmatter `summary` 를 인덱스의 단일 소스로 못 박는다(채택).** ADR·rules 와 **같은 규약·같은
  생성기·같은 검증**이 되어 축이 하나로 유지된다. `.SYNOPSIS` 는 셸 도움말로 남기되, 인덱스는 이를
  읽지 않는다 — 두 문장은 대상이 다른 별개의 산출물이지 사본이 아니다.

## 결정 (Decision)

- **스크립트 사용법은 `docs/scripts/<name>.md` 로 분리한다.** `scripts\<name>.ps1` ↔ `docs/scripts/<name>.md`
  가 이름으로 1:1 대응한다. 새 스크립트는 **새 파일만** 만들므로 공유 영역을 건드리지 않는다.
- **`docs/README.md` 는 입구로 남긴다.** 시작하기 · 공통 규칙(`-Service`·자동 발견·종료 코드) · `.env`
  레퍼런스 · 운영 메모 · 문제 해결은 그대로 두고, 사용법 자리에는 `docs/scripts/` 링크와 생성기
  안내만 둔다. **스크립트를 한 줄씩 나열하던 목록·트리는 제거한다**(그 자체가 append 지점이므로).
- **한 줄 요약의 단일 소스는 각 문서 맨 위 frontmatter `summary` 다.** `.SYNOPSIS` 는 `Get-Help` 용으로
  유지하되 인덱스 생성에는 쓰지 않는다(위 대안 A·B 기각).
- **`scripts/gen-docs-index.ps1` 이 scripts 인덱스도 생성한다.** `-Out` 은 `scripts-index.md` 를 함께 쓴다.
- **`-Check` 는 양방향 커버리지까지 검증한다.** (1) 모든 대상 문서의 `summary` 완비, (2) `scripts\*.ps1`
  마다 문서 존재(문서 없는 새 스크립트 차단), (3) 대응 스크립트가 사라진 고아 문서 차단.
  `lib\` 아래 공용 모듈(`_common.ps1`·`_devtools.ps1`)은 직접 실행하지 않으므로 대상이 아니다.
  이 양방향 점검은 `doctor.ps1` 의 "`.env` 접두사 ↔ compose 서비스 키" 검사와 같은 결이다.

## 결과 (Consequences)

- **좋은 점**: 스크립트를 추가하는 두 PR 을 병렬로 올려도 사용법 문서에서 충돌하지 않는다. #50 이
  지목한 최대 핫스팟이 구조적으로 사라진다.
- **좋은 점**: ADR·rules·scripts 세 축이 **하나의 규약**(frontmatter `summary`)과 **하나의 생성기**를
  공유한다. 새 축이 생겨도 같은 방식으로 붙는다.
- **좋은 점**: 문서 누락이 CI 에서 잡힌다. 예전에는 스크립트를 추가하고 문서를 잊어도 아무도
  알려주지 않았다.
- **감수할 점**: 사용법이 20여 개 파일로 흩어져, `docs/README.md` 하나를 훑어 전체를 파악하던
  경험이 사라진다. 폴더 목록과 생성 인덱스가 이를 대신한다([ADR-0021](0021-generated-doc-index.md) 이 이미 받아들인 절충).
- **감수할 점**: `.SYNOPSIS` 와 문서 요약이 서로 다른 문장으로 남는다. 의도된 분리지만, 스크립트
  동작을 크게 바꿀 때는 두 곳을 함께 살펴야 한다.
- **감수할 점**: 스크립트 이름을 바꾸면 문서 파일명도 함께 바꿔야 한다. 잊으면 `-Check` 가
  MissingDoc/OrphanDoc 두 건으로 알려 준다.
