# ADR-0015: 모든 작업은 worktree에서, main 병합은 PR + GitHub Actions CI로

- 상태: Accepted
- 관련: [ADR-0014](0014-internal-dev-loop.md), [ADR-0011](0011-batch-continue-on-error.md), [ADR-0012](0012-utf8-bom-for-powershell.md), `.github/workflows/ci.yml`, `scripts/check.ps1`

## 배경 (Context)

지금까지 "어떻게 변경을 만들고 main 에 넣는가"(브랜치 전략·병합 방식)가 문서로 남아 있지
않았다. main 에 직접 커밋·push 가 가능해 검증되지 않은 변경이 바로 들어갈 수 있었고,
로컬 검증([ADR-0014](0014-internal-dev-loop.md)의 `check.ps1`)은 선택 사항이라 강제되지
않았다. 또 여러 작업을 오가며 한 워킹트리에서 편집하면 작업 공간이 서로 섞였다.

## 결정 (Decision)

- 모든 코드/설정/문서 변경은 **git worktree** 에서 격리해 진행한다. main 워킹트리에서 직접
  편집·커밋하지 않는다.
  - `git worktree add -b <type>/<주제> <경로> main` 으로 브랜치와 작업 공간을 함께 만든다.
  - worktree 안에서 편집·커밋하고, 커밋 전 `.\scripts\check.ps1 -Test`([ADR-0014](0014-internal-dev-loop.md))로 검증한다.
- 완료되면 브랜치를 push 하고 **PR 로만** main 에 병합한다. **main 직접 push 는 하지 않는다.**
- **GitHub Actions CI**(`.github/workflows/ci.yml`)가 `push`·모든 `pull_request` 마다
  `check.ps1 -Test -Install`(린트 + doctor + Pester)을 windows-latest 에서 돌려 **병합 게이트**로 삼는다.
- 커밋 메시지는 conventional commits(CONVENTIONS §12), 릴리스는 CLAUDE.md 릴리스 절차를 따른다.

## 결과 (Consequences)

- **좋은 점**: main 이 항상 CI 통과 상태로 유지된다. 로컬 검증([ADR-0014](0014-internal-dev-loop.md))이
  선택에서 **병합 게이트**로 승격된다.
- **좋은 점**: worktree 격리로 여러 작업(및 병렬 서브에이전트)이 서로의 편집을 밟지 않고, main
  워킹트리는 늘 깨끗하다.
- **좋은 점**: PR 에 변경 이력·리뷰·CI 결과가 남아 되돌리기/추적이 쉽다.
- **감수할 점**: 1인 저장소에도 작은 변경마다 브랜치→PR→CI 왕복 오버헤드가 생긴다.
- **감수할 점**: worktree 디렉터리 관리 부담. 병합 후 `git worktree remove` 로 정리해야 한다.
