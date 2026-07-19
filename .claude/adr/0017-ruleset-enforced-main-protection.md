---
summary: "관례 → 강제. 필수 체크는 CI job 이름에 묶임"
---

# ADR-0017: main 보호는 관례가 아니라 Ruleset 으로 서버에서 강제한다

- 상태: Accepted
- 관련: [ADR-0015](0015-worktree-pr-github-actions.md), [ADR-0014](0014-internal-dev-loop.md), `.github/workflows/ci.yml`, [rules/workflow.md](../rules/workflow.md), [#22](https://github.com/Chigo55/Docker-Compose/issues/22)

## 배경 (Context)

[ADR-0015](0015-worktree-pr-github-actions.md)는 "worktree 에서 작업하고 PR 로만 main 에 병합하며,
CI 통과를 병합 게이트로 삼는다"고 결정했다. 그러나 그 결정은 **문서에만** 있었다. GitHub 쪽에는
아무 보호 규칙도 없어서 `git push origin main` 한 번이면 CI 를 거치지 않은 커밋이 그대로 들어갔다.

문서로만 있는 규칙은 급할 때 가장 먼저 깨진다. 1인 저장소에서는 특히 "이번만" 이 반복되고,
규칙 위반과 단순 실수를 구분해 줄 장치도 없다.

## 결정 (Decision)

저장소 Ruleset **`main protection`**(enforcement: active)으로 기본 브랜치를 **서버에서** 강제한다.

- **PR 필수** — main 직접 push 차단. 필요 승인 수는 **0**(1인 저장소라 자기 승인을 기다리다 막히지
  않게. 게이트는 사람 리뷰가 아니라 CI 다).
- **필수 상태 체크** — `lint + doctor + tests (PowerShell 5.1)`
  (= `.github/workflows/ci.yml` 의 job `name`). 통과 전에는 병합할 수 없다.
- **force push 금지**(non-fast-forward) · **브랜치 삭제 금지**.
- **bypass actor 없음** — owner 도 예외가 아니다.

## 결과 (Consequences)

- **좋은 점**: [ADR-0015](0015-worktree-pr-github-actions.md)가 관례에서 **강제**로 승격됐다.
  main 은 항상 "CI 통과 + PR 이력" 상태를 유지한다.
- **좋은 점**: 문서를 읽지 않은 사람(또는 에이전트)에게도 규칙이 적용된다. 실수로 main 에 push 하면
  서버가 거부한다.
- **감수할 점 · 함정**: 필수 상태 체크는 **job 이름 문자열**로 걸려 있다. `ci.yml` 의 `name:` 을 바꾸면
  ruleset 이 기다리는 체크가 영영 도착하지 않아 **모든 PR 이 병합 불가**가 된다(빨간 실패가 아니라
  "대기 중" 으로 조용히 멈춘다 — 원인을 찾기 어려운 종류의 사고다). 이름을 바꾸려면 ruleset 의
  required check 도 **같은 PR 에서 함께** 고쳐야 한다.
- **감수할 점**: `docs/` 한 줄을 고칠 때도 worktree → PR → CI 왕복이 강제된다. 이 비용이 학습 메모를
  저장소가 아니라 Wiki 에 두기로 한 근거가 됐다([ADR-0018](0018-wiki-for-learning-repo-for-code.md), [#26](https://github.com/Chigo55/Docker-Compose/issues/26)).
- **감수할 점**: 긴급 우회 경로가 없다. 필요하면 Settings → Rules 에서 ruleset 을 일시 해제해야 하며,
  그 행위 자체가 기록으로 남는다.
