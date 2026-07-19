---
summary: "GitHub 기능 지도 — ruleset·Actions 권한·dependabot·Wiki·Security 등 원격 설정 현황"
---

# GitHub 기능 지도 (원격에 실제로 켜져 있는 것)

이 저장소의 규칙 일부는 파일이 아니라 **GitHub 설정**에 있다. 저장소만 clone 해서는 보이지 않고,
어긴 줄도 모른 채 "왜 병합이 안 되지?" 로 만난다. 여기 그 지도를 둔다.

> 이 문서는 **현황 기록**이다. 설정을 바꿨다면 여기도 같이 고친다 — 안 그러면 문서가 아니라
> 설정이 단일 소스가 되고, 다음 사람은 UI 를 뒤져야 한다([ADR-0016](../adr/0016-track-in-github-not-docs.md)).

## 병합을 막는 것 — Ruleset `main protection`

**main 은 서버에서 보호된다**([ADR-0017](../adr/0017-ruleset-enforced-main-protection.md)). 관례가 아니라 강제다.

| 규칙 | 값 |
|------|-----|
| PR 필수 | ✅ (필요 승인 **0** — 게이트는 사람이 아니라 CI) |
| 필수 상태 체크 | **`lint + doctor + tests (PowerShell 5.1)`** |
| force push(non-fast-forward) · 브랜치 삭제 | ❌ 금지 |
| bypass actor | **없음** (owner 도 예외 아님) |

> ⚠️ **필수 상태 체크는 `.github/workflows/ci.yml` 의 job `name:` 문자열과 글자 그대로 묶여 있다.**
> 이름을 바꾸면 ruleset 이 기다리는 체크가 도착하지 않아 **모든 PR 이 "대기 중" 으로 멈춘다**(실패가
> 아니라서 원인 찾기가 어렵다). 바꾸려면 ruleset 의 required check 도 **같은 PR 에서 함께** 고친다.

## Actions

- **기본 워크플로 권한이 `read` 다.** 그래서 워크플로가 PR·이슈에 무언가를 **쓰려면 파일에서
  `permissions:` 를 직접 올려야 한다.** 안 올리면 실패하지 않고 **조용히 아무것도 안 남긴다** —
  Claude 리뷰가 매번 리뷰를 작성하고 폐기하던 [#27](https://github.com/Chigo55/Docker-Compose/issues/27)·[#30](https://github.com/Chigo55/Docker-Compose/issues/30) 이 이 원인이었다. 새 워크플로를 추가할 때 가장 먼저 확인할 것.

| 워크플로 | 트리거 | 하는 일 |
|----------|--------|---------|
| `ci.yml` | push(main/master) · 모든 PR | windows-latest + PS 5.1 에서 `check.ps1 -Test -Install`. **병합 게이트** |
| `claude-code-review.yml` | PR opened/synchronize/reopened/ready_for_review | Claude 자동 코드 리뷰 |
| `claude.yml` | 이슈·PR 코멘트의 `@claude` 멘션 | 멘션 응답 |

- 시크릿은 `CLAUDE_CODE_OAUTH_TOKEN` 하나(Claude 워크플로 2종이 사용). Environments·변수는 없다.
- `ci.yml` 의 `run:` 블록은 **ASCII 전용**([CLAUDE.md](../../CLAUDE.md) 참고). YAML 주석의 한글은 무방하다.
- **ADR·rules 인덱스는 워크플로가 아니라 로컬(`check.ps1`)에서 생성·검증한다**([ADR-0021](../adr/0021-generated-doc-index.md)).
  "병합 후 인덱스를 자동 커밋" 류를 안 쓴 이유가 여기 있다: main 은 Ruleset 으로 보호되어 **어떤 액터도 직접
  push 하지 못하고**([main protection](#병합을-막는-것--ruleset-main-protection)), `GITHUB_TOKEN` 으로 연 PR 은 CI 를 트리거하지 못해 필수 체크가 안 붙는다.
  그래서 표를 아예 커밋하지 않고(생성물), CI 는 각 파일의 `summary` frontmatter 완비만 검사한다.

## Dependabot

- `.github/dependabot.yml` — **`github-actions` 생태계만**, weekly([#23](https://github.com/Chigo55/Docker-Compose/issues/23)).
  docker(SQL Server 이미지 태그)·PowerShell 모듈은 대상이 아니다. 이미지 태그는 `compose/.env` 안의
  값이라 dependabot 이 읽지 못하고, 개발 모듈은 `-Install` 로 최신을 받는다.
- Dependabot PR(예: [#33](https://github.com/Chigo55/Docker-Compose/pull/33) checkout v4→v7)도 **같은 CI 게이트**를 통과해야 병합된다.
- Dependabot **alerts / security updates 는 비활성**이다(의존성 매니페스트가 사실상 워크플로뿐이라 얻을 게 적다).

## Issues · PR

- 템플릿: `.github/ISSUE_TEMPLATE/`(버그·기능 요청, 빈 이슈 허용) · `.github/pull_request_template.md`
  (저장소 고유의 함정을 체크리스트로 — BOM·ASCII·양쪽 켜기·3종 세트).
- 이슈 템플릿 선택 화면에는 `config.yml` 의 **contact_links** 로 보안 신고 창구가 붙어 있다 —
  취약점은 공개 이슈가 아니라 Security 탭의 비공개 신고로 간다(아래 [Security](#security)).
- 라벨: 기본 라벨 + `roadmap`(Project 항목) · `refactor` · `removed` · `test` · `dependencies`/`github_actions`(dependabot 자동 부여).
  이 중 **카테고리 라벨은 릴리스 노트 분류에도 쓰인다**(`enhancement`/`bug`/`documentation`/`refactor`/`removed`/의존성 → [`.github/release.yml`](../../.github/release.yml), [ADR-0020](../adr/0020-generate-release-notes-from-prs.md)). `removed` 는 이때 신설한 유일한 라벨이다.
- 병합 후 **원격 브랜치는 자동 삭제**된다(`delete_branch_on_merge`). 로컬 worktree 정리는 수동이다.
- 범위 밖에서 발견한 버그·위험은 커밋에 섞지 않고 `gh issue create` 로 분리한다([ADR-0016](../adr/0016-track-in-github-not-docs.md)).

## Project · 로드맵

- **Project #4 "SQL Server Farm 로드맵"**(owner Chigo55)이 로드맵의 단일 소스다. 필드: Status ·
  Priority · Effort · Type. 완료는 이슈 close → Status Done.
- **저장소 안에 로드맵 문서는 없다.** 동결 사본이던 `docs/ROADMAP.md` 는 실제와 어긋나 삭제했다
  ([ADR-0019](../adr/0019-remove-frozen-roadmap.md)). 초기 계획 원문이 필요하면 `git show v1.1.1:docs/ROADMAP.md`.
- 마일스톤은 쓰지 않는다(0건).

## Wiki

- [Wiki](https://github.com/Chigo55/Docker-Compose/wiki) 는 **학습 공간**이다 — Docker/SQL Server 개념처럼
  코드가 바뀌어도 늙지 않는 자료만 둔다([ADR-0018](../adr/0018-wiki-for-learning-repo-for-code.md)).
  저장소 About(`homepage`)이 여기를 가리킨다.
- **스크립트 사용법을 Wiki 에 복사하지 않는다.** 사용법의 단일 소스는 [docs/README.md](../../docs/README.md) 이고,
  Wiki 는 링크만 한다. Wiki 는 별도 git 저장소라 CI 도 PR 리뷰도 없어, 복사하면 조용히 낡는다.

## Security

| 기능 | 상태 |
|------|------|
| secret scanning | ✅ enabled |
| push protection | ✅ enabled — 평문 `.env` 설계([ADR-0013](../adr/0013-plaintext-password-gitignored.md))의 실질적 방어막 |
| private vulnerability reporting | ✅ enabled — Security 탭 → **Report a vulnerability** ([#28](https://github.com/Chigo55/Docker-Compose/issues/28)) |
| [`.github/SECURITY.md`](../../.github/SECURITY.md) | ✅ 신고 경로 · 지원 버전(최신 마이너만) · **"의도된 설계"**(평문 `.env` 오신고를 막는 항목) |
| code scanning | ❌ 없음 — **CodeQL 은 PowerShell 을 지원하지 않는다.** PSScriptAnalyzer 결과를 SARIF 로 올리는 방안을 [#24](https://github.com/Chigo55/Docker-Compose/issues/24) 에서 추적 |

push protection 의 한계는 [rules/secrets.md](secrets.md) 를 볼 것 — SA 비밀번호는 탐지 대상이 아니다.

## Discussions · Releases

- **Discussions 는 켜져 있지만 비어 있다**(기본 카테고리 6개, 글 0건). 정리와 릴리스 연결
  (`gh release create --discussion-category Announcements`)은 [#26](https://github.com/Chigo55/Docker-Compose/issues/26) 에서 추적 중이다.
  현재로선 논의 창구가 아니라 **이슈**를 쓴다.
- Releases: annotated 태그 `vX.Y.Z` + `gh release create vX.Y.Z --generate-notes`. **릴리스 노트는
  병합된 PR 에서 자동 생성**한다(라벨→카테고리 매핑 = [`.github/release.yml`](../../.github/release.yml)).
  수기 `CHANGELOG.md` `[Unreleased]` 관리는 **폐지**했다(병렬 PR 충돌 제거,
  [ADR-0020](../adr/0020-generate-release-notes-from-prs.md)·[#44](https://github.com/Chigo55/Docker-Compose/issues/44)).
  `CHANGELOG.md` 는 v1.1.1 까지의 과거 이력만 담는다. 최신은 v1.1.1 — 절차는 [CLAUDE.md](../../CLAUDE.md) 릴리스 항목.
