# 레퍼런스 — gh 명령 · Project 필드 ID · 인용 함정

절차가 아니라 **찾아보는 문서**다. 명령을 짜다 막혔을 때 여기를 본다.

## 인용·인코딩 함정 (실제로 걸린 것들)

### 1. 한국어 본문은 `--body-file` 로 넘긴다

이 저장소는 이슈·PR 본문을 한국어로 쓰고, 운영 셸은 Windows PowerShell 5.1 이다.
`--body "한국어..."` 로 직접 넘기면 콘솔 코드페이지(CP949)를 타면서 깨질 수 있다.
**파일에 UTF-8 로 쓰고 `--body-file`** 이 안전하다.

```powershell
# 본문을 UTF-8 파일로 쓰고 넘긴다 (PowerShell 5.1 의 Out-File 기본은 UTF-16 이라 -Encoding 필수)
$body | Out-File -FilePath issue.md -Encoding utf8
gh issue create --title "docs: ..." --body-file issue.md
Remove-Item issue.md
```

`gh pr create --fill` 은 커밋 메시지를 쓰므로 이 문제가 없다 — **가장 안전한 기본값**이다.

### 2. GraphQL 쿼리는 **한 줄로** 쓴다

`gh api graphql -f query='...'` 에 줄바꿈이 들어간 쿼리를 넘기면
`Expected NAME, actual: (none)` 로 실패한다(셸 종류와 무관하게 재현됨).

```bash
# ✅ 한 줄
gh api graphql -f query='query{user(login:"Chigo55"){projectV2(number:4){id title}}}'

# ❌ 여러 줄 — 파싱 실패
```

여러 줄이 꼭 필요하면 `-F query=@쿼리파일.graphql` 로 파일에서 읽는다.

### 3. `:owner/:repo` 플레이스홀더를 쓴다

`gh api` 는 `:owner`·`:repo` 를 현재 저장소로 치환한다. 저장소 이름을 하드코딩하면 worktree
밖에서 실행할 때 엉뚱한 곳을 가리킨다.

```bash
gh api repos/:owner/:repo/milestones     # ✅
```

단 **Project 는 저장소가 아니라 사용자 소유**라 치환이 안 된다 — `--owner Chigo55` 를 명시한다.

### 4. `--jq` 안의 인용

작은따옴표로 감싸면 PowerShell·bash 양쪽에서 동작한다. 안에 작은따옴표가 필요하면 `--jq` 대신
`--json` 으로 받아 별도 처리한다.

## Project #4 — ID 치트시트

`gh project item-edit` 는 이름이 아니라 **ID** 를 받는다. 아래 값은 조회 결과이며,
**Project 를 편집했다면 낡을 수 있다** — 어긋나면 [재조회](#id-재조회) 한다.

```
PROJECT_ID   PVT_kwHOBc19Pc4BdUvM
```

| 필드 | FIELD_ID | 옵션 → OPTION_ID |
|------|----------|------------------|
| `Status` | `PVTSSF_lAHOBc19Pc4BdUvMzhX3E-g` | Todo `f75ad846` · In Progress `47fc9ee4` · Done `98236657` |
| `Effort` | `PVTSSF_lAHOBc19Pc4BdUvMzhX3FEg` | S `a2530918` · M `27cfd181` · L `e3d73f08` |
| `Type` | `PVTSSF_lAHOBc19Pc4BdUvMzhX3FEk` | 🟢 신규 `1ab16b67` · 🟡 수정 `fac95cff` · 🟠 혼합 `bca1f6ee` |
| `Importance` | `PVTSSF_lAHOBc19Pc4BdUvMzhX3FDo` | High `e36cba53` · Medium `51cab849` · Low `120b46f3` |
| `Priority` | `PVTF_lAHOBc19Pc4BdUvMzhYJs4Y` | (숫자 필드 — 옵션 없음) |

### ID 재조회

```bash
gh api graphql -f query='query{user(login:"Chigo55"){projectV2(number:4){id fields(first:30){nodes{... on ProjectV2SingleSelectField{id name options{id name}} ... on ProjectV2Field{id name}}}}}}'
```

### Project 필드 편집

**항목 ID(`ITEM_ID`)는 이슈 번호가 아니다.** 먼저 목록에서 찾는다.

```bash
# 이슈 번호 → ITEM_ID
gh project item-list 4 --owner Chigo55 --limit 100 --format json \
  --jq '.items[] | "\(.content.number)\t\(.id)"'

# 단일 선택 필드 (Status·Effort·Type·Importance)
gh project item-edit --project-id PVT_kwHOBc19Pc4BdUvM --id <ITEM_ID> \
  --field-id PVTSSF_lAHOBc19Pc4BdUvMzhX3FEg --single-select-option-id 27cfd181   # Effort=M

# 숫자 필드 (Priority)
gh project item-edit --project-id PVT_kwHOBc19Pc4BdUvM --id <ITEM_ID> \
  --field-id PVTF_lAHOBc19Pc4BdUvMzhYJs4Y --number 3

# 값 지우기
gh project item-edit --project-id PVT_kwHOBc19Pc4BdUvM --id <ITEM_ID> \
  --field-id <FIELD_ID> --clear
```

여러 항목을 채울 때는 `ITEM_ID` 를 한 번에 조회해 두고 루프를 돌린다. 매 항목마다 목록을
다시 읽지 않는다.

## 자주 쓰는 조회

```bash
# 이슈 — 라벨·마일스톤·담당자까지
gh issue list --state open --limit 100 --json number,title,labels,milestone,assignees

# 특정 라벨이 없는 열린 이슈
gh issue list --state open --limit 100 --json number,title,labels \
  --jq '.[] | select([.labels[].name] | index("roadmap") | not) | "#\(.number) \(.title)"'

# PR 의 CI 상태 (필수 체크 통과 여부)
gh pr checks <번호>
gh pr view <번호> --json statusCheckRollup --jq '.statusCheckRollup[] | "\(.name) \(.conclusion)"'

# 마일스톤 진척률
gh api repos/:owner/:repo/milestones \
  --jq '.[] | "#\(.number) \(.title) \(.closed_issues)/\(.open_issues + .closed_issues)"'

# 서브이슈 (부모 → 자식)
gh api repos/:owner/:repo/issues/<부모번호>/sub_issues --jq '.[] | "#\(.number) [\(.state)] \(.title)"'

# 이슈의 database id (서브이슈 등록에 필요 — 번호가 아니다)
gh api repos/:owner/:repo/issues/<번호> --jq .id

# 릴리스 노트 미리보기 (태그 만들기 전)
gh api repos/:owner/:repo/releases/generate-notes \
  -f tag_name=<새태그> -f previous_tag_name=<이전태그> -f target_commitish=main --jq .body
```

## 자주 쓰는 쓰기 (승인 후에만)

```bash
gh issue create --title "<제목>" --body-file <파일> --label <라벨>
gh issue edit <번호>... --add-label <라벨> --remove-label <라벨> --milestone "<제목>"
gh issue close <번호> --comment "<이유>"          # Project Status 도 함께 Done 으로
gh project item-add 4 --owner Chigo55 --url <이슈 URL>
gh label edit <이름> --description "<설명>"
gh api repos/:owner/:repo/milestones -f title="<목표>" -f description="<완료 기준>"
gh api repos/:owner/:repo/issues/<부모>/sub_issues -f sub_issue_id=<자식 database id>
```

## 저장소 파일을 고쳐야 할 때

문서·워크플로·스크립트 변경은 `gh` 로 끝나지 않는다. **main 은 Ruleset 이 보호**하므로
worktree → PR 을 탄다([rules/workflow.md](../../../rules/workflow.md)).

```bash
git fetch origin main
git worktree add -b <type>/<주제> ../wt-<주제> origin/main
# ...편집... (새 ADR 이면 fetch 직후 ls .claude/adr/ 로 번호 재확인)
git push -u origin <type>/<주제>
gh pr create --fill --base main
gh pr edit <번호> --add-label <카테고리 라벨>      # 릴리스 노트 분류에 필요
```

- **커밋 전 `.\scripts\check.ps1 -Test`** (Windows). PowerShell 이 없는 환경에서는 돌릴 수
  없으므로 CI 에 위임하고, PR 본문에 그 사실을 적는다.
- 병합 후 `git worktree remove ../wt-<주제>` + 로컬 main `git pull --ff-only`.

## 이 스킬이 건드리지 않는 것

| 대상 | 이유 |
|------|------|
| 취약점 신고 | 공개 이슈 금지 — Security 탭 비공개 신고([SECURITY.md](../../../../.github/SECURITY.md)) |
| Wiki 편집 | 별도 git 저장소이고 학습 자료 전용([ADR-0018](../../../adr/0018-wiki-for-learning-repo-for-code.md)). 스크립트 사용법을 복사하지 않는다 |
| Discussions | 비어 있고 정리가 #26 에서 진행 중 — 논의는 이슈로 |
| `CHANGELOG.md` | 갱신하지 않는 파일([ADR-0020](../../../adr/0020-generate-release-notes-from-prs.md)) |
| ruleset 단독 변경 | `ci.yml` job 이름과 묶여 있어 [audit.md](audit.md) 의 4단계 순서를 따라야 한다 |
