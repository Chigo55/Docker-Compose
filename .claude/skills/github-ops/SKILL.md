---
name: github-ops
description: >-
  이 저장소의 GitHub 운영(이슈·라벨·Project #4·마일스톤·서브이슈·릴리스·원격 설정)을
  현황 브리핑 → 대화로 결정 → 승인 후 일괄 실행 순서로 함께 관리한다.
  "깃허브 관리", "이슈 정리", "트리아지", "백로그 정리", "라벨 붙여", "Project 갱신",
  "로드맵 정리", "마일스톤", "서브 이슈로 쪼개", "릴리스 낼까", "v1.2.0", "릴리스 노트",
  "깃허브 설정 점검", "드리프트 감사", "지금 뭐 할까" 같은 요청에 사용한다.
  개별 gh 명령을 즉흥적으로 조합하기 전에 이 스킬을 먼저 읽는다 — 이 저장소는
  Project 필드·라벨→릴리스 노트 매핑·ruleset 필수 체크 이름이 서로 묶여 있어
  한 곳만 건드리면 조용히 어긋난다.
---

# GitHub 운영 (github-ops)

이 저장소는 추적을 문서가 아니라 GitHub 으로 한다([ADR-0016](../../adr/0016-track-in-github-not-docs.md)).
그래서 **관리 부담이 저장소 밖에 쌓인다** — 이슈는 늘고, Project 필드는 비고, 라벨은 낡고,
원격 설정은 [rules/github.md](../../rules/github.md) 의 기록과 어긋난다. 이 스킬은 그 부담을
매번 즉흥적으로 처리하지 않도록 **읽기 → 브리핑 → 합의 → 일괄 실행** 순서로 고정한다.

## 원칙 세 가지

1. **읽기는 자유, 쓰기는 승인 후.** 조회·브리핑은 묻지 않고 한다. 라벨 부착·이슈 생성·Project
   필드 변경·마일스톤 배정·close·태그는 **"무엇을 어떻게 바꿀지" 목록을 먼저 내고 승인받은 뒤
   한꺼번에** 실행한다. 항목별로 하나씩 묻지 않는다(대화가 산만해진다).
2. **저장소가 아니라 GitHub 이 단일 소스.** 이 스킬은 상태를 저장소 파일에 복사해 두지 않는다.
   현황은 매번 `gh` 로 다시 읽는다. 낡은 사본을 만드는 순간 [ADR-0019](../../adr/0019-remove-frozen-roadmap.md) 의
   실수(동결된 `docs/ROADMAP.md`)를 되풀이한다.
3. **판단은 사용자가, 정리는 내가.** 우선순위·범위·릴리스 시점 같은 결정은 사용자에게 묻는다.
   누락 탐지·형식 통일·명령 조립은 묻지 않고 준비해 온다.

## 1단계 — 상태 수집 (항상 먼저, 예외 없음)

브리핑 없이 곧장 쓰기로 들어가지 않는다. 아래를 실행해 현재 상태를 확보한다.

```bash
# 열린 이슈 (라벨·마일스톤·담당자)
gh issue list --state open --limit 100 \
  --json number,title,labels,milestone,assignees,createdAt

# 열린 PR (라벨·CI 상태) — 라벨 없는 PR 은 릴리스 노트에서 "기타" 로 떨어진다
gh pr list --state open --limit 30 --json number,title,labels,isDraft,statusCheckRollup

# 마일스톤 진척률
gh api repos/:owner/:repo/milestones --jq '.[] | "#\(.number) \(.title) open:\(.open_issues) closed:\(.closed_issues)"'

# Project #4 항목 + 필드값 (로드맵의 단일 소스)
gh project item-list 4 --owner Chigo55 --limit 100 --format json

# 마지막 릴리스 이후 병합된 PR (릴리스 시점 판단용)
gh release view --json tagName,publishedAt 2>/dev/null || echo "(릴리스 없음)"
```

세부 명령·필드 ID·인용 함정은 [references/reference.md](references/reference.md) 에 있다.

## 2단계 — 브리핑 (관리가 새는 지점만 짚는다)

수집한 데이터를 그대로 나열하지 않는다. **사용자가 결정해야 할 것**만 골라 짧은 표로 낸다.
아래 8가지가 이 저장소에서 실제로 새는 지점이다. 매번 전부 확인한다.

| # | 점검 | 새는 방식 |
|---|------|-----------|
| 1 | 열린 이슈 중 Project #4 에 **없는** 것 | 로드맵 단일 소스에서 누락 — 잊힌다 |
| 2 | Project 항목 중 **Effort·Type·Priority 가 빈** 것 | Status 만 채워 등록하고 끝내는 습관 |
| 3 | 이슈 상태 ↔ Project Status **불일치** (닫혔는데 Todo / 열렸는데 Done) | close 시 Status Done 수동 전환을 빠뜨림 |
| 4 | **카테고리 라벨이 없는** 열린 PR | 릴리스 노트에서 "기타" 로 떨어짐([ADR-0020](../../adr/0020-generate-release-notes-from-prs.md)) |
| 5 | 마일스톤 진척률과 **마일스톤 없이 떠 있는** 관련 이슈 | 크로스컷 목표의 N/M 이 실제보다 좋게 보임 |
| 6 | 부모 이슈의 **서브이슈 상태** (다음 차례가 무엇인지) | 여러 파트 작업에서 두 번째 파트가 유실됨 |
| 7 | 마지막 릴리스 이후 **병합 PR 수와 라벨 상태** | 릴리스 시점을 놓치거나 노트가 비어 나옴 |
| 8 | 원격 설정 ↔ [rules/github.md](../../rules/github.md) **드리프트** | 문서가 현황 기록인데 설정만 바뀜 |

브리핑 끝에는 항상 **"먼저 무엇을 할까요?"** 로 사용자에게 공을 넘긴다. 스킬이 우선순위를
혼자 정하지 않는다.

## 3단계 — 대화로 결정, 4단계 — 승인 후 일괄 실행

사용자가 방향을 정하면 해당 절차 문서를 **그때 읽어서** 따른다.

| 하려는 일 | 읽을 문서 |
|-----------|-----------|
| 새 이슈 등록·라벨 정리·Project 등록/필드 채우기 | [references/triage.md](references/triage.md) |
| 여러 이슈에 걸친 목표 묶기 · 마일스톤 · 서브이슈로 쪼개기 | [references/plan.md](references/plan.md) |
| 릴리스 (태그 + 노트 자동 생성) | [references/release.md](references/release.md) |
| 원격 설정 감사 · 문서 드리프트 수정 | [references/audit.md](references/audit.md) |
| gh 명령·Project 필드 ID·인용 함정 | [references/reference.md](references/reference.md) |

실행 직전 승인 요청은 이 형식으로 낸다 — 되돌리는 방법까지 같이 적는다.

```
다음 12건을 실행합니다. 진행할까요?
  [라벨]      #61 #62 #64 에 roadmap 추가          (되돌리기: gh issue edit --remove-label)
  [Project]   #59~#65 Effort=M, Type=🟡 수정        (되돌리기: 필드 값 재설정)
  [마일스톤]  #53 → 마일스톤 없음 유지 (#50 서브이슈)  (변경 없음)
  [주의]      #46 은 v1.2.0 태그 전에 끝나야 함       (릴리스 차단 요소)
```

## 쓰기 전에 반드시 멈추는 것들

- **`ci.yml` 의 job `name:`** — 문자열이 ruleset 필수 체크 `lint + doctor + tests (PowerShell 5.1)`
  와 글자 그대로 묶여 있다. 바꾸면 체크가 도착하지 않아 **모든 PR 이 "대기 중"으로 멈춘다**.
  ruleset 을 같은 PR 에서 함께 고칠 때만 건드린다.
- **main 직접 push** — Ruleset `main protection` 이 서버에서 거부한다(bypass 없음, owner 도 예외
  아님). 저장소 파일 변경은 worktree → PR([rules/workflow.md](../../rules/workflow.md)).
- **이슈 close** — Project Status 를 Done 으로 함께 옮겨야 한다. 둘은 자동 연동이 아니다.
- **릴리스 태그** — 되돌리기 비싸다. 라벨 소급 정리가 끝났는지 먼저 확인([references/release.md](references/release.md)).

## 저장소 고유 사실 (외우지 말고 여기서 확인)

| 항목 | 값 |
|------|-----|
| Project | **#4 "SQL Server Farm 로드맵"**, owner `Chigo55` (사용자 소유, org 아님) |
| Project 필드 | `Status`(Todo/In Progress/Done) · `Effort`(S/M/L) · `Type`(🟢 신규/🟡 수정/🟠 혼합) · `Priority`(숫자 랭킹) · `Importance`(High/Medium/Low) |
| ruleset 필수 체크 | `lint + doctor + tests (PowerShell 5.1)` (승인 0명 — 게이트는 CI) |
| 카테고리 라벨 | `enhancement` · `bug` · `removed` · `refactor` · `dependencies`/`github_actions` · `documentation` (이 순서가 릴리스 노트 우선순위) |
| 추적 라벨 | `roadmap`(Project 항목) · `test`(검증 필요) |
| 열린 마일스톤 | #1 크로스 플랫폼 지원 (Windows · macOS · Linux) |
| 논의 창구 | **이슈** (Discussions 는 켜져 있으나 비어 있음 — 정리는 #26) |
| 취약점 | 공개 이슈 금지 → Security 탭 비공개 신고 |

> 이 표가 실제와 어긋나면 그것 자체가 드리프트다 — 발견하면 [references/audit.md](references/audit.md)
> 절차로 이 파일과 [rules/github.md](../../rules/github.md) 를 함께 고친다.
