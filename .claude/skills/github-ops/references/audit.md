# 감사 — 원격 설정 ↔ 문서 드리프트

[rules/github.md](../../../rules/github.md) 는 **현황 기록**이다. 설정은 GitHub UI 에서 바뀌고
문서는 저장소에서 바뀌므로, 둘은 자연히 어긋난다. 어긋난 줄도 모른 채 "왜 병합이 안 되지" 로
만나는 게 이 저장소의 실제 사고 패턴이었다.

이 절차는 **원격을 읽어 문서와 대조**한다. 릴리스 전, 워크플로/설정을 만진 뒤, 또는 한동안
관리하지 않았을 때 돌린다.

## 감사 실행 — 아래를 전부 조회한다

```bash
# 1) Ruleset — 필수 체크 이름·bypass·PR 필수
RS=$(gh api repos/:owner/:repo/rulesets --jq '.[] | select(.name=="main protection") | .id')
gh api repos/:owner/:repo/rulesets/$RS \
  --jq '{enforcement, bypass:(.bypass_actors|length), rules:[.rules[].type],
          checks:[.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[].context],
          approvals:[.rules[]|select(.type=="pull_request").parameters.required_approving_review_count][0]}'

# 2) Actions 기본 워크플로 권한 (read 여야 한다)
gh api repos/:owner/:repo/actions/permissions/workflow

# 3) 저장소 기능 · Security 상태
gh api repos/:owner/:repo \
  --jq '{has_wiki,has_discussions,delete_branch_on_merge,homepage,security_and_analysis}'

# 4) 라벨 (이름 + 설명)
gh label list --limit 60 --json name,description --jq '.[] | "\(.name)\t\(.description)"'

# 5) Project #4 필드 정의
gh api graphql -f query='{ user(login:"Chigo55"){ projectV2(number:4){
  fields(first:30){ nodes{
    ... on ProjectV2SingleSelectField { name options{name} }
    ... on ProjectV2Field { name dataType } } } } }'

# 6) 워크플로 파일의 permissions 선언
grep -n -A3 "^permissions:" .github/workflows/*.yml
```

## 대조 기준 — 이 값이 나와야 정상

문서([rules/github.md](../../../rules/github.md))가 주장하는 상태다. 다르면 드리프트다.

| 항목 | 기대값 | 어긋나면 생기는 일 |
|------|--------|-------------------|
| ruleset `enforcement` | `active` | 보호가 꺼져 main 직접 push 가 통과한다 |
| ruleset `bypass_actors` | **0개** | owner 예외가 생겨 ADR-0017 전제가 깨진다 |
| 필수 체크 `context` | `lint + doctor + tests (PowerShell 5.1)` | **모든 PR 이 "대기 중"으로 멈춘다** (실패가 아니라서 원인 찾기가 어렵다) |
| 필수 체크 개수 | 1개 | 이름이 바뀐 체크가 추가되면 둘이 되어 하나는 영영 안 온다 |
| PR 필수 승인 수 | `0` | 사람 리뷰 대기가 생긴다(게이트는 CI 라는 설계와 다름) |
| ruleset rules 종류 | `deletion` · `non_fast_forward` · `pull_request` · `required_status_checks` | 빠진 규칙만큼 보호에 구멍 |
| Actions `default_workflow_permissions` | `read` | 여기가 `write` 면 워크플로의 `permissions:` 누락이 감춰진다 |
| 워크플로 `permissions:` | 쓰기가 필요한 워크플로마다 **파일에서 명시** | **조용히 아무것도 안 남긴다**(#27·#30 의 원인) |
| `delete_branch_on_merge` | `true` | 병합된 브랜치가 쌓인다 |
| `secret_scanning` / `push_protection` | 둘 다 `enabled` | 평문 `.env` 설계의 방어막이 사라진다([ADR-0013](../../../adr/0013-plaintext-password-gitignored.md)) |
| `secret_scanning_non_provider_patterns` | `disabled` | **의도된 값이다** — SA 비밀번호는 탐지 대상이 아니라는 [rules/secrets.md](../../../rules/secrets.md) 기술이 여기 근거 |
| `dependabot_security_updates` | `disabled` | 의도된 값(의존성 매니페스트가 사실상 워크플로뿐) |
| `has_wiki` · `homepage` | `true` · Wiki URL | About 링크가 끊긴다 |
| Project 필드 | `Status`·`Effort`·`Type`·`Priority`·`Importance` | 문서에 없는 필드가 늘면 무엇을 채워야 할지 알 수 없다 |
| 라벨 설명 | 실재하는 대상을 가리켜야 함 | 삭제된 파일을 가리키는 설명은 다음 사람을 오도한다 |

## 드리프트를 찾았을 때 — 어느 쪽이 맞는지 **먼저 묻는다**

문서를 자동으로 설정에 맞추지 않는다. 설정이 실수로 바뀐 경우 문서를 고치면 **사고를 정당화**한다.

```
드리프트 2건을 찾았습니다. 어느 쪽이 맞습니까?

1. Project 에 문서에 없는 `Importance`(High/Medium/Low) 필드가 있고, 전 항목이 비어 있습니다.
   (a) 쓸 필드다 → 문서에 추가하고 `Priority` 와 역할을 구분한다
   (b) 실수로 만든 필드다 → Project 에서 삭제한다
   (c) 당장 결정 안 함 → 문서에 "미사용" 으로 기록만 한다

2. 라벨 `roadmap` 설명이 `docs/ROADMAP.md 항목` 입니다. 그 파일은 ADR-0019 로 삭제됐습니다.
   → 설명을 실재하는 대상(Project #4)으로 고치는 게 맞아 보입니다. 진행할까요?
```

### 고칠 곳이 어디인가

| 드리프트 유형 | 고치는 방법 |
|---------------|-------------|
| 설정이 틀림 (ruleset·권한·라벨 설명) | `gh` 로 **원격 설정**을 고친다. 저장소 PR 불필요 |
| 문서가 낡음 | [rules/github.md](../../../rules/github.md)(+ [SKILL.md](../SKILL.md) 의 고유 사실 표)를 **worktree → PR** 로 고친다 |
| 설계 판단이 바뀜 | **ADR 을 새로 쓴다**. 기존 ADR 을 조용히 편집하지 않는다 |

라벨 설명 수정 예:

```bash
gh label edit roadmap --description "Project #4 로드맵 항목"
```

`ci.yml` job 이름과 ruleset 필수 체크가 어긋난 경우는 **동시 수정이 필수**다 — 워크플로 PR 이
병합되는 순간부터 새 이름의 체크가 오는데, ruleset 은 옛 이름을 기다린다. 워크플로 PR 을 열기
**전에** ruleset 을 고치면 그 PR 자신이 병합 불가가 된다. 순서는:

1. 워크플로 PR 을 만든다(아직 병합 안 함).
2. ruleset 의 required check 에 **새 이름을 추가**한다(옛 이름도 남긴 채, 둘 다).
3. PR 이 새 이름 체크로 통과하면 병합한다.
4. ruleset 에서 **옛 이름을 제거**한다.

## 감사 결과 보고

문서와 일치하는 항목은 나열하지 않는다. **어긋난 것과 판단이 필요한 것만** 낸다.

```
감사 완료 — 원격 설정 13개 항목 대조
  ✅ ruleset(active·bypass 0·필수체크 1개 일치) · Actions read · secret scanning · push protection
  ⚠️ Project 필드 `Importance` 가 문서에 없음 (전 항목 미입력)
  ⚠️ 라벨 `roadmap` 설명이 삭제된 docs/ROADMAP.md 를 가리킴
  📋 위 2건은 어느 쪽이 맞는지 결정이 필요합니다.
```
