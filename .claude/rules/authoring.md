---
summary: "새 스크립트 작성 · compose 직접 실행"
---

# 새 스크립트 작성 · compose 직접 실행

## 새 스크립트를 만들 때

- `scripts/lib/_common.ps1`의 자동 발견/헬퍼(`Get-Instances`, `Get-TargetInstances`,
  `Resolve-Services`, `Invoke-Compose`, `Invoke-Sql`, `Test-ContainerRunning`)를 **재사용**한다.
  발견·검증·SQL 실행을 새로 구현하지 말 것([ADR-0007](../adr/0007-shared-common-library.md)).
- 배치 작업은 continue-on-error + 요약 표 + 실패 시 `exit 1` 패턴을 따른다([ADR-0011](../adr/0011-batch-continue-on-error.md)).
- 파괴적 작업은 영향 목록을 Yellow 로 출력 → `-Force` 없으면 `계속하시겠습니까? (y/N)` 프롬프트 →
  거부 시 `return`. (`down.ps1`/`restore.ps1` 참조)
- 코드 스타일 전반은 [CONVENTIONS.md](../CONVENTIONS.md)를 따른다.
- **사용법 문서 `docs/scripts/<name>.md` 를 함께 만든다**(맨 위 `summary` frontmatter). 스크립트와
  문서는 이름으로 1:1 대응하고, 목록 표는 생성물이라 커밋하지 않는다([ADR-0022](../adr/0022-per-script-docs.md)).
  `docs/README.md` 나 인덱스 표에 줄을 추가하지 말 것 — 문서 누락·고아 문서는
  `gen-docs-index.ps1 -Check`(= `check.ps1` 3단계)가 잡는다.
- **편집 후 커밋 전 `.\scripts\check.ps1 -Test`로 검증**한다(린트 + doctor + 단위 테스트).
  순수 로직을 추가/수정했다면 `tests/`에 테스트도 함께 쓴다([ADR-0014](../adr/0014-internal-dev-loop.md), [CONVENTIONS.md](../CONVENTIONS.md) §13).

## compose 직접 실행

- compose.yml/.env 가 `compose/` 안에 있으므로, 손으로 `docker compose`를 돌릴 땐 그 폴더에서:
  ```powershell
  Push-Location .\compose; docker compose config; Pop-Location
  ```
  스크립트를 통할 땐 `Invoke-Compose`가 `-f`/`--env-file`을 자동으로 붙인다([ADR-0008](../adr/0008-explicit-compose-file-flags.md)).
