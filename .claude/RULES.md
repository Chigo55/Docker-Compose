# 편집 규칙 (RULES)

이 문서는 이 저장소를 **안전하게 고치기 위한 가드레일**이다. 대부분의 규칙은 어기면
"조용한 기동 실패"나 "손상된 백업" 같은, 즉시 드러나지 않는 사고로 이어진다.
결정의 배경은 [ADR](adr/README.md)에, 코드 스타일은 [CONVENTIONS](CONVENTIONS.md)에 있다.

> 대부분의 규칙은 `.\scripts\doctor.ps1`이 자동 점검한다. **편집 후 기동 전 `doctor.ps1`을 돌린다.**

## 1. `.env` 형식 (compose/.env)

- **`$`는 `$$`로 이스케이프**한다. compose 변수 확장 규칙 때문이다. — 단, [비밀번호에는 예외](#5-비밀번호).
- **Windows 경로도 슬래시 `/`를 쓴다** (`DATA_ROOT=C:/docker`). 역슬래시 금지.
- **주석은 값 옆이 아니라 윗줄에 단다.** 값 뒤 인라인 주석(`KEY=값  # 설명`)은 `Read-DotEnv`가
  주석을 값의 일부로 읽어 포트·비밀번호를 깨뜨린다.
- 값은 모두 ASCII 로, 한글은 주석에만 둔다([ADR-0012](adr/0012-utf8-bom-for-powershell.md)).

## 2. 인스턴스 추가/변경 (규약의 핵심)

한 인스턴스 = 접두사가 같은 **3종 세트**다([ADR-0002](adr/0002-instance-autodiscovery.md)).

- 추가 시: **`compose/.env`에 3줄**(`<PREFIX>_NAME` / `<PREFIX>_PORT` / `<PREFIX>_DIR`) +
  **`compose/compose.yml`에 서비스 블록**(`<<: *mssql2019` 또는 `*mssql2022` 병합).
- **서비스키 = `<PREFIX>`.ToLower()** 이고, `compose.yml`의 서비스 키와 **반드시 일치**해야 한다.
- **스크립트는 손대지 않는다.** 인스턴스 목록은 `.env` 스캔으로 자동 발견된다.
- 호스트 포트는 인스턴스마다 유일해야 하고, `_DIR`(데이터 폴더)도 인스턴스끼리 공유 금지.
- 컨테이너명(`_NAME`)과 폴더명(`_DIR`)은 **다르게 둘 수 있다**(예: 이관 시 `_DIR=Db2019A-old`).
  기존 DB 경로 호환을 위한 것이니 **임의로 통일하지 말 것**.

## 3. 선택 항목은 양쪽을 함께 켠다

`MSSQL_MEMORY_LIMIT_MB`, `MSSQL_AGENT_ENABLED`는 선택 항목이다. 쓰려면 **`compose/.env`와
`compose/compose.yml`의 대응 줄을 둘 다 주석 해제**해야 한다. 한쪽만 풀면 빈 값이 넘어가
컨테이너가 기동에 실패한다.

## 4. 데이터 안전

- 데이터는 호스트 바인드 마운트에 있다([ADR-0004](adr/0004-host-bind-mount-for-data.md)). `down.ps1`은
  컨테이너만 지우고 **데이터는 보존**한다.
- **백업은 반드시 `backup.ps1`(엔진 `BACKUP DATABASE`)로** 한다. 실행 중 인스턴스의 `.mdf`를
  직접 복사하면 손상된 사본이 나온다([ADR-0005](adr/0005-engine-based-backup.md)).
- `start.ps1`이 기동 전 데이터 폴더를 만든다. 이 순서를 우회해 수동으로 올리지 말 것(빈 폴더가
  생기면 기존 DB 를 못 붙는다).

## 5. 비밀번호

- `MSSQL_SA_PASSWORD`는 `.env`에 평문으로 있고, 실값 `.env`는 `.gitignore` 대상이다.
  팀에는 값을 비운 `.env.example`만 공유한다([ADR-0013](adr/0013-plaintext-password-gitignored.md)).
- 정책: **8자 이상 + 대문자/소문자/숫자/기호 중 3종 이상**.
- 비밀번호에는 **`$$`를 쓰지 말 것.** compose 는 `$$`→`$`로 해석하지만 스크립트(`Invoke-Sql`)는
  `.env` 원문을 그대로 쓰므로, `$$`가 있으면 backup/query/restore 인증이 어긋난다([ADR-0009](adr/0009-password-via-env-var.md)).

## 6. 이미지 / sqlcmd 경로

- sqlcmd 경로는 `.env`의 `MSSQL_2019_SQLCMD` / `MSSQL_2022_SQLCMD` 두 곳에만 있다. 이미지
  갱신으로 경로가 바뀌면 **여기만** 고친다([ADR-0006](adr/0006-sqlcmd-version-autodetect.md)).

## 7. 변경 반영 (restart 주의)

- 옵션 없는 `restart.ps1`은 `.env`의 **포트/이미지/볼륨 변경을 반영하지 못한다.** 이 경우
  `restart.ps1 -Recreate`(또는 `start.ps1 -Recreate`)를 쓴다.

## 8. 새 스크립트를 만들 때

- `scripts/lib/_common.ps1`의 자동 발견/헬퍼(`Get-Instances`, `Get-TargetInstances`,
  `Resolve-Services`, `Invoke-Compose`, `Invoke-Sql`, `Test-ContainerRunning`)를 **재사용**한다.
  발견·검증·SQL 실행을 새로 구현하지 말 것([ADR-0007](adr/0007-shared-common-library.md)).
- 배치 작업은 continue-on-error + 요약 표 + 실패 시 `exit 1` 패턴을 따른다([ADR-0011](adr/0011-batch-continue-on-error.md)).
- 파괴적 작업은 영향 목록을 Yellow 로 출력 → `-Force` 없으면 `계속하시겠습니까? (y/N)` 프롬프트 →
  거부 시 `return`. (`down.ps1`/`restore.ps1` 참조)
- 코드 스타일 전반은 [CONVENTIONS.md](CONVENTIONS.md)를 따른다.
- **편집 후 커밋 전 `.\scripts\check.ps1 -Test`로 검증**한다(린트 + doctor + 단위 테스트).
  순수 로직을 추가/수정했다면 `tests/`에 테스트도 함께 쓴다([ADR-0014](adr/0014-internal-dev-loop.md), [CONVENTIONS.md](CONVENTIONS.md) §13).

## 9. compose 직접 실행

- compose.yml/.env 가 `compose/` 안에 있으므로, 손으로 `docker compose`를 돌릴 땐 그 폴더에서:
  ```powershell
  Push-Location .\compose; docker compose config; Pop-Location
  ```
  스크립트를 통할 땐 `Invoke-Compose`가 `-f`/`--env-file`을 자동으로 붙인다([ADR-0008](adr/0008-explicit-compose-file-flags.md)).
