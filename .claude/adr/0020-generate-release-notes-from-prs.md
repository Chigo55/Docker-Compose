# ADR-0020: 릴리스 노트를 병합된 PR 에서 자동 생성한다 — 수기 `[Unreleased]` 폐지

- 상태: Accepted
- 관련: [ADR-0016](0016-track-in-github-not-docs.md)(추적은 문서가 아니라 GitHub 으로), [ADR-0015](0015-worktree-pr-github-actions.md)(PR-당-변경), 이슈 [#44](https://github.com/Chigo55/Docker-Compose/issues/44)

## 배경 (Context)

`CHANGELOG.md` 의 `[Unreleased]` 섹션을 **PR 마다 수기로** 채워 왔다([#38](https://github.com/Chigo55/Docker-Compose/issues/38)에서 v1.1.1 이후분을 정리). 이 방식은 병렬 작업량에 정비례해 비용이 커진다.

- 여러 PR 을 동시에 진행하면 각 PR 이 같은 `[Unreleased]` 블록에 줄을 더해, **같은 영역을 건드리는 병합 충돌**이 반복된다.
- 충돌은 실패가 아니라 마찰이다 — 매번 손으로 풀어야 하고, 잘못 풀면 남의 항목이 조용히 사라진다.
- 이 저장소는 이미 **추적을 문서가 아니라 GitHub 으로** 옮겼다([ADR-0016](0016-track-in-github-not-docs.md)). 릴리스 노트만 수기 문서에 남아 그 원칙과 어긋나 있었다.

검토한 대안:

- **A. `.gitattributes` union 병합 드라이버**(`CHANGELOG.md merge=union`) — 양쪽 추가분을 자동 보존해 하드 충돌만 없앤다. 비용은 거의 0 이지만 순서·중복을 보장하지 못하고, **B 를 채택하면 per-PR 편집 자체가 사라져 무의미**해진다. 채택 안 함.
- **C. 조각 파일**(changie/towncrier) — 충돌은 없지만 PowerShell 운영 레포에 외부 툴·빌드 단계를 들이는 비용이 과하다. 채택 안 함.

## 결정 (Decision)

- **수기 `[Unreleased]` 관리를 폐지한다.** 평상시 아무도 `CHANGELOG.md` 를 건드리지 않으므로 충돌이 원천 소멸한다.
- **릴리스 노트는 릴리스 시점에 병합된 PR 에서 자동 생성한다.** [`.github/release.yml`](../../.github/release.yml) 로 **라벨→카테고리** 매핑을 정의하고, `gh release create vX.Y.Z --generate-notes` 로 직전 태그 이후 병합된 PR 을 묶는다. 워크플로·외부 액션이 없어(로컬 `gh` 실행) [Actions 기본 권한 `read` 함정](../rules/github.md#actions)에 걸리지 않는다.
  - Release Drafter 같은 액션형 대안은 `contents: write` 권한이 필요해 같은 함정(#27·#30)에 걸릴 수 있다. 네이티브 `--generate-notes` 는 이 문제가 없다.
- **`CHANGELOG.md` 는 과거 이력만 보존한다.** `[1.0]`~`[1.1.1]` 은 이미 릴리스된 **불변 사실**이라 드리프트하지 않으므로 그대로 둔다. `[Unreleased]` 섹션은 **제거**한다 — 갱신을 멈추면 새 PR 이 병합될수록 실제와 어긋나(동결 문서가 겪던 드리프트, [ADR-0019](0019-remove-frozen-roadmap.md)), 반쯤 관리되는 섹션이 오히려 오해를 부른다. 파일 상단에 "v1.2.0 부터 릴리스 노트는 GitHub Releases 에서 자동 생성한다" 는 안내를 남겨 새 이력을 찾는 사람을 Releases 로 보낸다.
- **PR 라벨을 카테고리 분류에 재사용한다.** 새 라벨 세트를 만들지 않고 기존 라벨을 그대로 쓴다: `enhancement`→추가, `bug`→수정, `documentation`→문서, `refactor`→변경, `dependencies`/`github_actions`→의존성. 없던 **`removed` 라벨 하나만 신설**하고, 미분류 PR 은 catch-all `*`→기타 로 떨어진다.

## 결과 (Consequences)

- **좋은 점**: 평상시 CHANGELOG 를 건드리지 않으므로 병렬 PR 의 CHANGELOG 충돌이 사라진다.
- **좋은 점**: 릴리스 노트 작성이 릴리스 1회(자동)로 압축되고, 라벨만 붙으면 카테고리가 자동 정렬된다. 라벨은 어차피 트리아지에서 붙는다.
- **좋은 점**: [ADR-0016](0016-track-in-github-not-docs.md)의 "추적은 GitHub 으로" 와 결이 맞고, 로컬 `gh` 실행이라 Actions 권한 함정을 피한다.
- **감수할 점**: 노트 품질이 **PR 제목**에 달린다. conventional-commit 제목(feat/fix/…) 규율이 곧 릴리스 노트 품질이 된다. 제목이 모호하면 노트도 모호하다.
- **감수할 점**: 분류가 **PR 라벨**에 의존한다. 라벨을 안 붙이면 "기타" 로 떨어진다. `--generate-notes` 결과는 릴리스 전에 편집할 수 있으니 필요하면 손으로 보정한다.
- **감수할 점(전환기)**: 이 결정 이전에 병합된 v1.1.1 이후 PR 들은 카테고리 라벨이 없을 수 있다. v1.2.0 을 자동 생성할 땐 그 PR 들을 소급 라벨링하거나 생성 결과를 손보정한다. 이후 릴리스부터는 라벨이 상시 붙어 매끄럽다.
- **감수할 점**: 새 릴리스 노트가 이제 GitHub Releases 에 산다. 저장소만 clone 한 사람은 `[1.1.1]` 까지만 파일에서 보고, 그 이후는 Releases 탭을 봐야 한다(파일 상단 안내가 가리킨다).
