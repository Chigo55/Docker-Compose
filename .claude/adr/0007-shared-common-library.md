---
summary: "자동 발견/헬퍼 재사용, 하드코딩 금지"
---

# ADR-0007: 공통 로직은 `_common.ps1`에 모으고 dot-source 한다

- 상태: Accepted
- 관련: [ADR-0002](0002-instance-autodiscovery.md), [ADR-0008](0008-explicit-compose-file-flags.md), `scripts/lib/_common.ps1`

## 배경 (Context)

start/stop/status/backup/restore/query/logs/doctor 등 스크립트가 많고, 이들은 `.env` 읽기,
인스턴스 발견, `-Service` 검증, compose 호출, SQL 실행 같은 일을 공유한다. 스크립트마다
같은 코드를 복사하면 동작이 미세하게 갈라지고 유지보수가 어렵다.

## 결정 (Decision)

공통 함수를 `scripts/lib/_common.ps1` 한 곳에 두고, 모든 스크립트가 상단에서
`. "$PSScriptRoot\lib\_common.ps1"`로 **dot-source** 한다. 이 모듈은 자기 위치에서 저장소
루트(`$RepoRoot`)와 `compose/`의 절대경로를 역산해 둔다. 제공 함수:

- `Read-DotEnv`(캐시), `Get-Instances`(자동 발견), `Resolve-Services`(오타 검증),
  `Get-TargetInstances`(`-Service` 필터), `Invoke-Compose`, `Assert-Docker`,
  `Test-ContainerRunning`, `Get-SqlcmdInvocation`, `Invoke-Sql`.

**새 로직은 스크립트에 하드코딩하지 말고 이 헬퍼를 재사용**하고, 재사용거리가 반복되면
`_common.ps1`에 새 헬퍼로 올린다.

## 결과 (Consequences)

- **좋은 점**: 발견·검증·실행 규약이 한 곳에 있어 모든 스크립트가 일관되게 동작한다.
- **좋은 점**: `-Service` 오타 검증, compose 플래그 명시 등 안전장치가 자동으로 상속된다.
- **감수할 점**: `_common.ps1`을 바꾸면 전 스크립트에 영향이 가므로 시그니처 변경은 신중해야 한다.
- **감수할 점**: `_common.ps1`은 직접 실행하지 않는 순수 라이브러리라는 규약을 지켜야 한다.
