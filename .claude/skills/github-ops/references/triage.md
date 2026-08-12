# 트리아지 — 이슈 등록 · 라벨 · Project 등록

새 항목을 받아들이고, 이미 있는 항목의 분류를 바로잡는 절차. 진입점은
[SKILL.md](../SKILL.md) 이며 여기 오기 전에 1단계 상태 수집이 끝나 있어야 한다.

## A. 새 이슈를 만들 때

### 1. 먼저 물어볼 것 — 이슈로 만들 일인가

- **지금 작업의 일부** → 이슈로 만들지 않고 그 PR 에서 끝낸다.
- **범위 밖에서 발견한 버그·위험** → 이슈로 분리한다. 현재 커밋에 섞지 않는다([ADR-0016](../../../adr/0016-track-in-github-not-docs.md)).
- **여러 이슈가 모여야 끝나는 목표** → 이슈 하나로 만들지 말고 [plan.md](plan.md) 로 간다.
- **개념 설명·학습 자료** → 이슈도 저장소도 아니고 Wiki([ADR-0018](../../../adr/0018-wiki-for-learning-repo-for-code.md)).

### 2. 제목 — `<영역>: <관찰된 사실 또는 하려는 것>`

이 저장소의 실제 관례다. 영역은 파일명·서브시스템·문서 종류를 그대로 쓴다.

```
docs: CLAUDE.md 집약 영역(구조 트리·명령 목록) 지역화 (#50 C.3)
CI: ci.yml 을 windows-latest 단일에서 3-OS 매트릭스로 확장 (ruleset 필수 체크 이름 동반 수정)
ADR: 셸 런타임 정책 — pwsh 7 크로스 플랫폼 양립과 PowerShell 5.1 하위호환 범위 결정
리팩토링: 경로 조립의 역슬래시 하드코딩 제거 — 비Windows pwsh 에서 dot-source 가 즉사
rotate-password.ps1: 실 SQL Server 통합 검증 필요 (파괴적·미검증)
```

- **결과가 아니라 증상을 적는다**(버그). "왜 안 되지" 가 아니라 "무엇이 관찰됐다".
- 상위 이슈의 파트라면 `(#50 C.3)` 처럼 **부모 번호와 파트 기호**를 괄호로 붙인다.
- 부제가 필요하면 `—`(em dash)로 잇는다. 콜론을 두 번 쓰지 않는다.

### 3. 본문 — 왜 지금 문제인지가 핵심

템플릿(`.github/ISSUE_TEMPLATE/`)이 있으면 따르고, `--body` 로 직접 쓸 때는 최소 이 세 조각:

```markdown
## 현상 / 배경
(무엇이 관찰됐는가. 재현 경로나 해당 파일:줄)

## 왜 문제인가
(조용히 실패하는가? 데이터가 위험한가? 다음 사람이 어떻게 걸려 넘어지는가)

## 관련
(ADR·rules·이슈·PR 링크. 근거가 있는 결정이면 반드시 링크)
```

**조용한 실패인지 명시한다.** 이 저장소의 사고 대부분이 그 형태였다(권한 `read` 로 리뷰가
사라진 #27·#30, 번호가 겹친 ADR #55→#56). 눈에 안 띄는 실패는 그 사실 자체가 우선순위 근거다.

### 4. 라벨 — 카테고리 하나 + 추적 라벨

| 성격 | 라벨 |
|------|------|
| 새 기능·스크립트·옵션 추가 | `enhancement` |
| 동작이 잘못됨 (조용한 실패 포함) | `bug` |
| 문서·ADR·rules·주석 | `documentation` |
| 구조 개선·중복 제거·기술부채 | `refactor` |
| 기능/파일 제거 | `removed` |
| 실기기 검증·테스트가 필요 | `test` |
| Project 로드맵 항목 | `roadmap` (카테고리와 **겹쳐 붙인다**) |

> **이슈 라벨과 PR 라벨을 혼동하지 말 것.** 릴리스 노트는 **PR 라벨만** 읽는다
> (`.github/release.yml`). 이슈에 `enhancement` 를 붙여도, 그 일을 한 PR 에 라벨이 없으면
> 노트에서 "기타" 로 떨어진다. 트리아지에서 이슈를 정리했다고 릴리스 준비가 된 게 아니다 —
> [release.md](release.md) 를 따로 확인한다.

여러 카테고리 라벨이 붙으면 노트는 **첫 매칭 하나**로 분류한다. 순서는
`enhancement` → `bug` → `removed` → `refactor` → `dependencies`/`github_actions` → `documentation`.
문서 위주 작업에 `enhancement` 를 같이 붙이면 "추가(Added)" 로 올라간다 — 의도한 게 아니라면
PR 에는 카테고리 라벨을 **하나만** 붙인다.

### 5. Project #4 등록 — 이슈 생성과 별개 단계다

`gh issue create` 는 Project 에 넣지 않는다. **등록을 빠뜨리면 로드맵에서 사라진다**(SKILL.md
브리핑 점검 1번).

```bash
gh issue create --title "<제목>" --body "<본문>" --label enhancement,roadmap
gh project item-add 4 --owner Chigo55 --url https://github.com/Chigo55/Docker-Compose/issues/<번호>
```

등록 후 **필드를 그 자리에서 채운다.** 나중에 하면 안 한다(현재 #53·#59~#65 가 그 증거).
필드 편집 명령은 [reference.md](reference.md#project-필드-편집) 에 있다.

| 필드 | 채우는 기준 |
|------|-------------|
| `Status` | 착수 전 `Todo` · 작업 중 `In Progress` · 완료 `Done` |
| `Effort` | `S` 한 PR 로 끝남 · `M` 한 PR 이지만 설계 판단 필요 · `L` 쪼개야 함(→ [plan.md](plan.md)) |
| `Type` | `🟢 신규` 없던 것 추가 · `🟡 수정` 있는 것 고침 · `🟠 혼합` 둘 다 |
| `Priority` | 숫자 랭킹. **비워도 된다** — 순위를 매길 때만 채운다 |
| `Importance` | High/Medium/Low. 현재 전 항목 미사용 — 쓰기로 정하면 `Priority` 와 역할을 먼저 구분한다 |

## B. 이미 있는 이슈를 정리할 때

브리핑에서 잡힌 누락을 **묶어서** 처리한다. 하나씩 묻지 않는다.

```bash
# 카테고리 라벨 없는 열린 이슈 찾기
gh issue list --state open --limit 100 --json number,title,labels \
  --jq '.[] | select([.labels[].name] | any(. == "enhancement","bug","documentation","refactor","removed") | not) | "#\(.number) \(.title)"'

# 라벨 일괄 부착 / 제거
gh issue edit 61 62 64 --add-label roadmap
gh issue edit 46 --remove-label documentation --add-label enhancement
```

### 상태 불일치 바로잡기

닫힌 이슈가 Project 에서 `Todo` 로 남아 있거나 그 반대인 경우다. **이슈 close 와 Project
Status 는 자동 연동이 아니다.**

```bash
# 닫힌 이슈인데 Status ≠ Done 인 항목 찾기 (수동 대조)
gh project item-list 4 --owner Chigo55 --limit 100 --format json \
  | python3 -c "import json,sys; [print(i.get('status'), i['content'].get('number'), i['content'].get('title','')[:40]) for i in json.load(sys.stdin)['items']]"
gh issue list --state closed --limit 100 --json number --jq '[.[].number] | sort'
```

교차 확인해 어긋난 것만 목록으로 내고, 승인 후 Status 를 일괄 갱신한다.

### 중복·무효 정리

- 같은 문제를 다루는 이슈가 둘이면 **늦게 만든 쪽을 닫고** `duplicate` 라벨 + 남길 쪽 링크를
  코멘트로 남긴다. 조용히 닫지 않는다.
- 전제가 사라진 이슈(예: 참조 파일이 삭제됨)는 닫기 전에 **왜 무효가 됐는지**를 코멘트에
  적는다. 근거가 ADR 이면 링크한다.

## C. 트리아지 결과 보고

작업 후 사용자에게 이 형태로 요약한다.

```
정리 완료
  라벨 부착   3건 (#61 #62 #64 ← roadmap)
  Project 등록 2건 (#64 #65)
  필드 입력   8건 (Effort·Type)
  상태 정정   1건 (#52 Todo → Done)
남은 결정
  #46 Priority 미정 — v1.2.0 릴리스 차단 요소입니다. 순위를 정할까요?
```
