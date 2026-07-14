# 작업 흐름 (worktree · PR · 추적)

## 변경은 worktree 에서 만들고 PR 로 병합한다

모든 코드/설정/문서 변경은 **worktree 에서** 한다. main 워킹트리에서 직접 편집·커밋하지
않는다([ADR-0015](../adr/0015-worktree-pr-github-actions.md)).

```powershell
git worktree add -b <type>/<주제> ..\wt-<주제> main   # 브랜치 + 격리 작업 공간 생성
# ...편집...
.\scripts\check.ps1 -Test                              # 커밋 전 검증(린트 + doctor + 테스트)
git push -u origin <type>/<주제>                       # push
gh pr create --fill --base main                        # PR 로만 병합
git worktree remove ..\wt-<주제>                       # 병합 후 정리
```

- **main 직접 push 금지.** main 병합은 오직 PR 로만 한다.
- **GitHub Actions CI**(`.github/workflows/ci.yml`)가 PR·push 마다 `check.ps1 -Test` 를
  windows-latest 에서 돌린다. **CI 통과가 병합 조건**이다.
- 커밋은 conventional commits([CONVENTIONS §12](../CONVENTIONS.md)), 릴리스는
  [CLAUDE.md](../../CLAUDE.md)의 릴리스 절차를 따른다.

## 추적은 문서가 아니라 GitHub 으로 한다

[ADR-0016](../adr/0016-track-in-github-not-docs.md).

- **로드맵·추후 업데이트** → GitHub Project "SQL Server Farm 로드맵"(#4) + `roadmap` 라벨 이슈.
  `docs/ROADMAP.md` 는 동결이라 갱신하지 않는다.
- **작업 중 발견한 범위 밖 버그·위험** → 현재 작업에 섞지 말고 `gh issue create` 로 등록한다.
