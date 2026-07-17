# ADR-0016: 로드맵·버그·위험은 문서가 아니라 GitHub(Project·Issues)로 추적한다

- 상태: Accepted — 단, **`docs/ROADMAP.md` 를 동결 보존한다는 조항은 [ADR-0019](0019-remove-frozen-roadmap.md) 로 대체됨**(파일은 삭제됨). Project·Issues 를 단일 소스로 삼는 결정 자체는 유효하다.
- 관련: [ADR-0015](0015-worktree-pr-github-actions.md), [ADR-0001](0001-env-single-source-of-truth.md), [ADR-0019](0019-remove-frozen-roadmap.md)

## 배경 (Context)

로드맵을 `docs/ROADMAP.md`(문서)로도, `roadmap` 라벨 이슈로도, GitHub Project 로도 관리하면
같은 정보를 세 곳에서 갱신하게 되어 드리프트가 생긴다. 마찬가지로 작업 중 발견한 범위 밖
버그·위험을 대화나 문서에만 적으면 추적을 잃는다. ".env 가 유일한 설정 소스"([ADR-0001](0001-env-single-source-of-truth.md))
처럼, 추적에도 **단일 소스**가 필요하다.

## 결정 (Decision)

- **로드맵·추후 업데이트 항목** → GitHub Project "SQL Server Farm 로드맵"(#4,
  `https://github.com/users/Chigo55/projects/4`) + `roadmap` 라벨 이슈가 단일 소스다.
  신규 등록·상태 갱신(Todo/In Progress/Done)은 Project·이슈에서 한다.
- **작업 중 발견한 범위 밖 버그·위험·quirk** → 대화·문서 대신 `gh issue create` 로 등록하고,
  현재 작업 커밋에 섞지 않는다(후속 항목으로 분리).
- `docs/ROADMAP.md` 는 **동결**된 초기 스냅샷으로만 남기고 갱신하지 않는다(상단 동결 배너 유지).
- 요약하면, **상태·추적은 문서가 아니라 GitHub 으로 관리한다.**

## 결과 (Consequences)

- **좋은 점**: 로드맵·이슈의 단일 소스가 명확해져 삼중 관리·드리프트가 사라진다.
- **좋은 점**: Project 보드에서 우선순위(P1~P3)·노력도·상태를 한눈에 본다.
- **감수할 점**: `gh`/Project 접근 권한(토큰 `project` scope)이 필요하다. 오프라인·권한 없는
  환경에선 즉시 등록이 어렵다.
- **감수할 점**: `docs/ROADMAP.md` 는 시간이 지나며 실제 상태와 어긋난다(동결 문서이므로 의도된
  것 — 최신 상태 참조는 Project 로).
