# 릴리스 — 태그 + 노트 자동 생성

노트는 **수기 `CHANGELOG.md` 가 아니라 병합된 PR 에서 생성**한다([ADR-0020](../../../adr/0020-generate-release-notes-from-prs.md)).
그래서 릴리스 품질은 **PR 라벨이 제대로 붙어 있는지**에 전부 달려 있다. 태그를 만든 뒤에는
고치기 비싸므로, 아래 순서를 건너뛰지 않는다.

현재 최신은 **v1.1.1**. `CHANGELOG.md` 는 그 시점까지의 과거 이력만 담고 **갱신하지 않는다**
(`[Unreleased]` 수기 관리 폐지 — 병렬 PR 충돌 제거).

## 1. 노트를 먼저 미리 본다 (태그 없이)

태그를 만들기 **전에** 결과물을 볼 수 있다. 이 단계에서 라벨 문제가 다 드러난다.

```bash
gh api repos/:owner/:repo/releases/generate-notes \
  -f tag_name=v1.2.0 -f previous_tag_name=v1.1.1 -f target_commitish=main \
  --jq .body
```

미리보기를 사용자에게 **그대로 보여주고** 확인받는다. 볼 것:

- **"기타 (Other)" 섹션에 무엇이 있는가** → 카테고리 라벨이 없는 PR 이다. 그 상태로 릴리스하면
  변경 내역이 분류되지 않은 채 남는다.
- **엉뚱한 섹션에 있는 PR** → 라벨이 여러 개 붙어 첫 매칭으로 끌려간 경우
  (순서: `enhancement` → `bug` → `removed` → `refactor` → `dependencies`/`github_actions` → `documentation`).
- **비어 있는 섹션** → 정상이다. 없는 카테고리는 출력되지 않는다.

## 2. 라벨 소급 정리 (v1.1.1 → v1.2.0 전환기 잔여 작업)

**이슈 #46 이 정확히 이 일이다.** ADR-0020 이전에 병합된 PR 에는 카테고리 라벨이 없어,
지금 릴리스하면 대부분 "기타" 로 떨어진다.

```bash
# v1.1.1 이후 병합된 PR 과 라벨 상태
gh release view v1.1.1 --json publishedAt --jq .publishedAt
gh pr list --state merged --base main --limit 200 \
  --json number,title,labels,mergedAt \
  --jq '.[] | select(.mergedAt > "<위 publishedAt>") | "#\(.number) [\([.labels[].name] | join(","))] \(.title)"'
```

라벨이 빈 PR 목록을 뽑아 **"PR 번호 → 붙일 라벨" 표로 승인받은 뒤** 일괄 부착한다.

```bash
gh pr edit 55 --add-label refactor
gh pr edit 54 --add-label documentation
```

PR 제목의 conventional commit 타입이 그대로 힌트다: `feat:`→`enhancement` ·
`fix:`→`bug` · `docs:`→`documentation` · `refactor:`→`refactor`.
**카테고리 라벨은 PR 당 하나만** 붙인다(첫 매칭 규칙 때문).

정리를 끝냈으면 **1번 미리보기를 다시 돌려** 결과를 확인하고, 이슈 #46 을 닫으면서 Project
Status 도 Done 으로 옮긴다.

## 3. 버전 결정

`CHANGELOG.md` 가 아니라 **1번 미리보기 내용**을 근거로 정한다.

| 변경 | 범프 |
|------|------|
| 하위호환 기능 추가 (새 스크립트·새 옵션) | **마이너** (v1.1.1 → v1.2.0) |
| 버그 수정·문서만 | 패치 (v1.1.1 → v1.1.2) |
| 기존 사용법이 깨짐 (`.env` 키 제거, 스크립트 인자 변경) | 메이저 |

`.env` 키 이름 변경이나 스크립트 인자 제거는 **사용자의 운영 환경을 깨뜨린다**. 릴리스 노트
"제거 (Removed)" 항목이 있으면 메이저인지 반드시 사용자에게 확인한다.

## 4. 태그 + 릴리스 생성

태그는 **main 에서, annotated 로** 만든다. 로컬 main 이 최신인지 먼저 확인한다.

```bash
git checkout main && git pull --ff-only origin main
git log --oneline -1                      # 태그가 붙을 커밋 확인

git tag -a v1.2.0 -m "v1.2.0"
git push origin v1.2.0

gh release create v1.2.0 --generate-notes --verify-tag --title "v1.2.0"
```

- `--verify-tag` — 태그가 원격에 없으면 실패한다. lightweight 태그가 조용히 생기는 것을 막는다.
- `--generate-notes` — `.github/release.yml` 의 카테고리 매핑을 적용한다.
- **`--discussion-category` 는 아직 쓰지 않는다** — Discussions 정리가 이슈 #26 에서 진행 중이다.

## 5. 사후 확인

```bash
gh release view v1.2.0 --json tagName,name,body,publishedAt --jq '.body'
```

- 노트가 의도대로 분류됐는지.
- **`CHANGELOG.md` 를 고치지 않았는지** — 갱신하지 않는 파일이다. 실수로 편집했다면 되돌린다.
- 릴리스에 포함된 이슈들의 Project Status 가 모두 `Done` 인지([triage.md](triage.md#상태-불일치-바로잡기)).

## 되돌리기

태그를 잘못 냈을 때. **이미 공개된 태그는 지우지 않는 게 원칙**이지만, 방금 만들었고 아무도
받아가지 않았다면 즉시 정리한다.

```bash
gh release delete v1.2.0 --yes        # 릴리스만 삭제 (태그는 남음)
git push origin --delete v1.2.0       # 원격 태그 삭제
git tag -d v1.2.0                     # 로컬 태그 삭제
```

노트 문구만 문제라면 태그를 건드리지 말고 노트를 고친다 — 훨씬 안전하다.

```bash
gh release edit v1.2.0 --notes-file <파일>
```

> 태그 삭제는 ruleset 의 브랜치 삭제 금지와 별개다(태그는 보호 대상이 아니다). 그래도 릴리스를
> 이미 알린 뒤라면 삭제하지 말고 **패치 릴리스로 정정**하는 쪽을 사용자에게 권한다.
