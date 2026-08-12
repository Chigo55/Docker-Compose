---
summary: "작업 흐름 — worktree·PR·CI 게이트, 로드맵/버그는 GitHub 으로 추적"
---

# 작업 흐름 (worktree · PR · 추적)

## 변경은 worktree 에서 만들고 PR 로 병합한다

모든 코드/설정/문서 변경은 **worktree 에서** 한다. main 워킹트리에서 직접 편집·커밋하지
않는다([ADR-0015](../adr/0015-worktree-pr-github-actions.md)).

```powershell
git fetch origin main                                        # ★ 먼저 최신 main 을 받는다
git worktree add -b <type>/<주제> ..\wt-<주제> origin/main   # 브랜치 + 격리 작업 공간 생성
# ...편집...
.\scripts\check.ps1 -Test                                    # 커밋 전 검증(린트 + doctor + 테스트)
git push -u origin <type>/<주제>                             # push
gh pr create --fill --base main                              # PR 로만 병합
git worktree remove ..\wt-<주제>                             # 병합 후 정리
```

- **브랜치는 로컬 `main` 이 아니라 fetch 한 `origin/main` 에서 딴다.** 로컬 main 은 마지막 pull
  시점에 멈춰 있어서, 그 사이 병합된 PR 을 못 본 채로 작업하게 된다.
  > ⚠️ **번호로 이름 짓는 파일**(`.claude/adr/NNNN-*.md`)이 특히 위험하다. stale 한 main 에서
  > 브랜치를 따면 이미 쓰인 번호를 다시 집는데, **파일명이 다르면 git 도 CI 도 충돌을 잡지
  > 못한다** — 병합되고 나서야 같은 번호 ADR 이 둘인 걸 발견한다([#55](https://github.com/Chigo55/Docker-Compose/pull/55)→[#56](https://github.com/Chigo55/Docker-Compose/pull/56) 이 이 사고였다).
  > 새 ADR 을 만들기 전 fetch 직후 `ls .claude\adr\` 로 다음 번호를 다시 확인한다.
- **main 직접 push 는 서버가 거부한다.** 관례가 아니라 Ruleset `main protection` 으로 강제된다
  (PR 필수 · force push/삭제 금지 · **bypass 없음 — owner 도 예외 아님**). [ADR-0017](../adr/0017-ruleset-enforced-main-protection.md)
- **GitHub Actions CI**(`.github/workflows/ci.yml`)가 PR·push 마다 `check.ps1 -Test` 를
  windows-latest 에서 돌린다. 이 job 은 ruleset 의 **필수 상태 체크**(`lint + doctor + tests (PowerShell 5.1)`)라
  통과 전에는 병합 버튼이 열리지 않는다. 승인은 0명이라 사람 리뷰를 기다리지는 않는다.
  > ⚠️ `ci.yml` 의 job `name:` 을 바꾸면 필수 체크가 영영 도착하지 않아 **모든 PR 이 병합 불가**가 된다.
  > 바꾸려면 ruleset 도 함께 고친다([rules/github.md](github.md)).
- PR 을 열면 **Claude 자동 코드 리뷰**(`claude-code-review.yml`)가 붙고, 코멘트에서 `@claude` 로 부를 수 있다.
- **Dependabot PR**(github-actions, weekly)도 같은 CI 게이트를 통과해야 병합한다.
- 병합되면 **원격 브랜치는 자동 삭제**된다. 로컬 worktree 는 `git worktree remove` 로 직접 정리한다.
- 커밋은 conventional commits([CONVENTIONS §12](../CONVENTIONS.md)), 릴리스는
  [CLAUDE.md](../../CLAUDE.md)의 릴리스 절차를 따른다.
- 원격에 켜져 있는 GitHub 기능 전체(Actions 권한·Security·Wiki·Discussions 등)는 [rules/github.md](github.md) 에 정리돼 있다.

## 추적은 문서가 아니라 GitHub 으로 한다

[ADR-0016](../adr/0016-track-in-github-not-docs.md).

- **로드맵·추후 업데이트** → GitHub Project "SQL Server Farm 로드맵"(#4) + `roadmap` 라벨 이슈.
  저장소 안에 로드맵 문서는 두지 않는다([ADR-0019](../adr/0019-remove-frozen-roadmap.md)).
- **작업 중 발견한 범위 밖 버그·위험** → 현재 작업에 섞지 말고 `gh issue create` 로 등록한다.
