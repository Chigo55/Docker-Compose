---
summary: "어느 폴더에서 실행해도 동일 동작"
---

# ADR-0008: compose 호출 시 `-f`/`--env-file`을 항상 명시한다

- 상태: Accepted
- 관련: [ADR-0001](0001-env-single-source-of-truth.md), [ADR-0007](0007-shared-common-library.md), `scripts/lib/_common.ps1` (`Invoke-Compose`)

## 배경 (Context)

`compose.yml`과 `.env`는 저장소 루트가 아니라 `compose/` 폴더 안에 있다. `docker compose`는
기본적으로 현재 폴더에서 이 파일들을 찾으므로, 사용자가 저장소 루트에서 `.\scripts\...`를
실행하면 파일을 찾지 못하거나 엉뚱한 파일을 쓸 수 있다.

## 결정 (Decision)

compose 호출을 `_common.ps1`의 `Invoke-Compose`로 단일화하고, 이 함수가 **항상**
`-f <compose/compose.yml> --env-file <compose/.env>`를 하위 명령(up/down/...) 앞에
붙인다. 경로는 `$RepoRoot` 기준 절대경로다. 스크립트는 실행 시작 시 `Set-Location $RepoRoot`도 한다.

## 결과 (Consequences)

- **좋은 점**: 어느 폴더에서 스크립트를 호출해도 동일한 파일 세트로 동작한다.
- **좋은 점**: compose 전역 옵션이 하위 명령 앞에 오는 순서 실수를 원천 차단한다.
- **감수할 점**: compose 를 직접 손으로 실행할 땐(예: `docker compose config` 검증) `compose/`
  폴더로 이동해서 실행해야 한다(`Push-Location .\compose; ...; Pop-Location`).
