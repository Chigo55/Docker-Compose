# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 개요

SQL Server 2019/2022 인스턴스 여러 개를 Docker Compose로 운영하는 인프라 템플릿입니다. (아래 예시는 8개)
**운영(ops) 저장소**이며, 산출물은 PowerShell 관리 스크립트입니다.
모든 조작은 Windows + PowerShell 5.1 이상 + Docker Desktop 환경을 전제로 합니다.
스크립트/설정을 고칠 때 쓰는 **내부 개발 루프**(린트·규약점검·단위테스트)는 선택 도구로 `scripts/check.ps1`·`scripts/test.ps1`에 있습니다(아래 참고). 실사용 운영에는 필요 없습니다.

## 로드맵

로드맵은 **GitHub Project "SQL Server Farm 로드맵"**(owner Chigo55, 저장소에 link됨)과 `roadmap` 라벨 이슈로 관리합니다. 신규 항목 등록·상태 갱신은 Project에서 하고(완료 시 이슈 close → Status Done), `docs/ROADMAP.md`는 **동결된 초기 스냅샷**이라 편집하지 않습니다.

## 리포지토리 구조

```
scripts/            관리 스크립트 (여기서 실행)
  lib/_common.ps1   공통 함수 모음 (ops, 직접 실행하지 않음)
  lib/_devtools.ps1 개발 루프 전용 헬퍼 (모듈 확보/파일 감시, 직접 실행하지 않음)
  *.ps1             start/stop/restart/status/logs/query/backup/restore/doctor/down
  check.ps1         내부 개발 루프: 린트 + doctor(+compose 렌더링) [+ -Test]
  test.ps1          Pester 단위 테스트 실행 (Pester 5+ 필요)
tests/
  _common.Tests.ps1 _common.ps1 자동 발견/파싱 로직 단위 테스트
compose/
  compose.yml       컨테이너 구조 정의 (설정값 없음)
  .env              모든 설정값 (Git 제외)
  .env.example      .env 견본 (비밀번호 비움)
docs/README.md      사용자 문서
docs/ROADMAP.md     로드맵 초기 스냅샷 — 동결됨(단일 소스는 GitHub Project, 아래 "로드맵" 참고)
.claude/            설계 문서 (adr/, rules/, CONVENTIONS.md)
CLAUDE.md           이 파일
```

## 자주 쓰는 명령

스크립트가 곧 명령입니다. 모두 **저장소 루트에서 `\.scripts\...` 형태로** 실행합니다. 각 스크립트는 `lib\_common.ps1`을 dot-source한 뒤 작업 폴더를 `$RepoRoot`로 맞추고, `Invoke-Compose`가 `-f compose/compose.yml --env-file compose/.env`를 명시적으로 넘기므로 어디서 호출해도 됩니다.

```powershell
.\scripts\start.ps1 -Pull                       # 이미지 최신본 받고 전체 기동
.\scripts\start.ps1 -Service db2019c,db2022e    # 일부만 기동
.\scripts\status.ps1                            # 상태/헬스/포트응답/데이터용량 표
.\scripts\status.ps1 -Watch                     # 5초마다 갱신
.\scripts\logs.ps1 db2019c -Follow              # compose 로그 실시간
.\scripts\logs.ps1 db2019c -ErrorLog            # SQL Server 자체 errorlog (compose 로그와 다름)
.\scripts\restart.ps1 -Recreate                 # .env 변경(포트/이미지/볼륨) 반영
.\scripts\query.ps1 "SELECT @@VERSION"          # 전 인스턴스에 T-SQL 일괄 실행
.\scripts\backup.ps1 -Database MyDb -Verify     # 엔진 백업 + 무결성 검증
.\scripts\restore.ps1 -Service db2019c -Database MyDb  # 최신 백업 복원 (WITH MOVE 자동)
.\scripts\doctor.ps1                            # 기동 전 .env/compose 규약 점검
.\scripts\down.ps1                              # 컨테이너/네트워크 제거 (데이터 보존)

# .env 렌더링 결과 확인 (적용 전 검증) — compose.yml 과 .env 가 compose/ 안에 있으므로 그 폴더에서 실행
Push-Location .\compose; docker compose config; Pop-Location
```

### 내부 개발 루프 (스크립트/설정 편집 시)

운영이 아니라 **이 저장소를 고칠 때** 쓰는 검증 루프입니다. 실패 시 종료 코드 1(자동화 감지용).

```powershell
.\scripts\check.ps1                 # 린트(PSScriptAnalyzer) + doctor(+compose 렌더링) 1회
.\scripts\check.ps1 -Test           # 위 + Pester 단위 테스트까지
.\scripts\check.ps1 -Watch -Test    # 파일 저장 때마다 전체 루프 자동 재실행 (편집→즉시 피드백)
.\scripts\test.ps1                  # Pester 단위 테스트만
.\scripts\check.ps1 -Install        # 없는 개발 모듈(PSScriptAnalyzer/Pester)을 CurrentUser 로 설치
```

- 개발 모듈은 **선택 의존성**입니다. 없으면 해당 단계만 건너뛰며(노란 안내), `-Install` 로 부트스트랩합니다.
- 린트 제외 규칙은 `check.ps1` 의 `$ExcludedRules` 에 있습니다(제외 이유 주석 포함): `PSAvoidUsingWriteHost`·`PSUseSingularNouns`·`PSReviewUnusedParameter`·`PSAvoidUsingPlainTextForPassword`(평문 SA 비번 설계, ADR-0013)·`PSUseShouldProcessForStateChangingFunctions`(수동 y/N 프롬프트 관례, CONVENTIONS §9).
- 테스트는 **Pester 5 이상**이 필요합니다(Windows 기본 3.4.0 은 문법이 달라 안 씀).
- **`compose/.env` 가 없으면(gitignore)** `check.ps1` 의 doctor 단계가 멈춥니다. 값·규약만 검증할 땐 `compose/.env.example` 을 복사해 `MSSQL_SA_PASSWORD` 만 정책 충족 더미로 채운 임시 `.env` 로 돌리고 지웁니다(CI 도 동일).
- Docker 가 꺼져 있으면 doctor 는 compose 렌더링을 건너뛰지만 종료 코드가 새어 `check.ps1` 이 실패로 보일 수 있습니다(이슈 #3). 이땐 doctor 자체 요약 `오류 N건` 으로 판단하세요.
- CI(`.github/workflows/ci.yml`)의 `run:` 블록은 **ASCII 전용**으로 유지합니다. GitHub 이 BOM 없는 임시 `.ps1` 로 저장하고 러너의 Windows PowerShell 5.1 이 한글을 ANSI 로 오독해 파싱이 깨집니다(최상위 YAML 주석의 한글은 무방).

단일 인스턴스만 다룰 때는 대부분의 스크립트가 `-Service <소문자 서비스키>`를 받습니다. 서비스키는 `.env` 접두사(prefix)의 소문자입니다(예: `DB2019C_*` → `db2019c`).

## 아키텍처: 왜 이렇게 구성했는가

여러 파일에 걸쳐 있어 한 파일만 봐서는 놓치기 쉬운 핵심 설계입니다.

### 1. `.env`가 유일한 설정 소스, 인스턴스는 자동 발견

- `compose/compose.yml`은 **구조만** 정의합니다(설정값 없음). YAML 앵커(`x-mssql-2019`, `x-mssql-2022`, `x-base`)로 공통 정의를 재사용합니다.
- 인스턴스 목록은 하드코딩되어 있지 않습니다. `scripts/lib/_common.ps1`의 `Get-Instances`가 `compose/.env`에서 **`<PREFIX>_PORT` 키를 스캔**(단, `MSSQL_PORT`는 제외)해 인스턴스를 만들고, 같은 접두사의 `_NAME`/`_DIR`을 함께 읽습니다.
- 따라서 **`<PREFIX>` 3종 세트(`_NAME`, `_PORT`, `_DIR`)가 규약의 핵심**입니다. 서비스키 = `<PREFIX>`.ToLower() 이고, 이 값이 `compose/compose.yml`의 서비스 키와 반드시 일치해야 합니다.

**인스턴스 추가 시**: `compose/.env`에 3줄 추가 + `compose/compose.yml`에 서비스 블록 추가(서비스 키 = prefix 소문자, `<<: *mssql2019` 또는 `*mssql2022` 병합). 스크립트는 손대지 않습니다 — `.env`를 스캔하기 때문입니다.

### 2. 2019 vs 2022 — sqlcmd 경로가 다르다

- 2019: `/opt/mssql-tools/bin/sqlcmd`, 2022: `/opt/mssql-tools18/bin/sqlcmd -C` (`-C`는 인증서 신뢰).
- 헬스체크는 `compose/.env`의 `MSSQL_2019_SQLCMD` / `MSSQL_2022_SQLCMD`를 사용합니다. 이미지 갱신으로 경로가 바뀌면 **여기만** 고칩니다.
- `_common.ps1`의 `Get-SqlcmdInvocation`은 두 후보 경로를 컨테이너에서 `test -x`로 실제 확인하고 캐시합니다. 즉 백업 등 스크립트 SQL 실행은 버전을 자동 판별합니다.

### 3. 데이터 안전 모델 (건드릴 때 반드시 이해)

- 데이터는 호스트 바인드 마운트(`DATA_ROOT/<XXX_DIR>/data` → `/var/opt/mssql/data`)에 있습니다. 그래서 `down.ps1`으로 컨테이너를 지워도 **데이터는 보존**됩니다.
- `start.ps1`은 기동 전에 데이터 폴더를 먼저 만듭니다. 폴더가 없는 채로 올리면 Docker가 빈 폴더를 생성해 **기존 DB를 못 붙기** 때문입니다.
- 백업은 **반드시 `backup.ps1`(엔진 `BACKUP DATABASE`)로** 합니다. 실행 중 인스턴스의 `.mdf`를 직접 복사하면 손상된 사본이 나옵니다.
- 기본 마운트는 `data`만입니다. errorlog(`/var/opt/mssql/log`)·secrets는 그대로 두면 컨테이너와 함께 사라지지만, **선택적으로 보존**할 수 있습니다: `compose/.env`의 `MOUNT_LOG_SECRETS=true`와 `compose/compose.yml` 각 서비스 `volumes`의 log/secrets 마운트 두 줄 주석을 **함께** 해제하면, `start.ps1`이 `DATA_ROOT/<XXX_DIR>/log`·`secrets` 폴더를 만들고 호스트에 보존합니다.

### 4. `scripts/lib/_common.ps1` — 모든 스크립트의 공용 기반

각 스크립트 상단에서 `. "$PSScriptRoot\lib\_common.ps1"`로 dot-source 합니다. 이 모듈은 자기 위치(`scripts/lib`)에서 두 단계 위를 저장소 루트(`$RepoRoot`)로 역산하고, `compose/` 안의 `compose.yml`·`.env` 절대경로를 미리 계산해 둡니다. 핵심 함수:
`Read-DotEnv`(캐시, 기본 경로 = `compose/.env`), `Get-Instances`(자동 발견), `Resolve-Services`(오타 검증 — 잘못된 `-Service`면 사용 가능 목록과 함께 throw), `Get-TargetInstances`(`-Service` 필터링된 인스턴스 목록 — start/backup/logs 공용), `Invoke-Compose`(항상 `-f`/`--env-file`을 명시), `Invoke-Sql`(비밀번호를 `SQLCMDPASSWORD` 환경변수로 넘겨 셸 인용 문제 회피; `-Separator`를 주면 다중 컬럼 결과를 그 문자로 구분해 파싱 가능 — `restore.ps1`의 `RESTORE FILELISTONLY`가 사용).

## 편집 시 주의사항

- **`compose/.env` 값의 `$`는 `$$`로 이스케이프**해야 합니다(compose 변수 확장 규칙).
- **Windows 경로도 `.env`에서는 슬래시 `/`**를 씁니다(`DATA_ROOT=C:/docker`).
- **`.env` 주석은 값 옆이 아니라 윗줄에** 답니다. 값 뒤 인라인 주석(`KEY=값  # 설명`)은 `Read-DotEnv`가 값의 일부로 읽어 포트·비밀번호를 깨뜨릴 수 있어 쓰지 않습니다.
- `restart.ps1`(옵션 없음)은 `.env`의 포트/이미지/볼륨 변경을 **반영하지 못합니다**. 이 경우 `-Recreate`를 쓰세요.
- 컨테이너명(`_NAME`)과 폴더명(`_DIR`)을 다르게 둘 수 있습니다(예: 기존 데이터 이관 시 컨테이너 `Db2019A` ↔ 폴더 `Db2019A-old`). 기존 DB 경로 호환을 위한 것이니 임의로 통일하지 마세요.
- `MSSQL_MEMORY_LIMIT_MB`, `MSSQL_AGENT_ENABLED`는 선택 항목입니다. 쓰려면 `compose/.env`와 `compose/compose.yml`의 대응 줄을 **둘 다** 주석 해제해야 합니다(한쪽만 풀어 빈 값이 넘어가면 기동 실패).
- `MOUNT_LOG_SECRETS`(errorlog·secrets 보존)도 같은 "양쪽 함께 켜기" 항목입니다. 다만 compose 쪽은 `${VAR}` 참조가 아니라 각 서비스 `volumes`의 log/secrets 마운트 주석을 해제하는 방식이고, 이 플래그(`compose/.env`)는 `start.ps1`이 폴더를 만들지를 결정합니다(§3 데이터 안전 모델 참고).
- `MSSQL_SA_PASSWORD`가 `compose/.env`에 평문으로 있습니다. 실제 값이 든 `compose/.env`는 `.gitignore`로 제외되어 있고, 팀에는 값을 지운 `compose/.env.example`만 커밋/공유합니다.

## 코드 규약 (기존 스크립트와 일관성 유지)

- 모든 `.ps1`은 `#Requires -Version 5.1`, `$ErrorActionPreference = 'Stop'`, comment-based help(`.SYNOPSIS`/`.EXAMPLE`)로 시작합니다.
- **`.ps1` 파일은 UTF-8 with BOM으로 저장**합니다. 한국어 Windows의 PowerShell 5.1은 BOM이 없는 UTF-8을 ANSI(CP949)로 잘못 읽어 한글 주석·출력이 깨지고, 최악의 경우 파싱이 실패합니다. BOM을 제거하는 편집기/도구로 저장했다면 다시 UTF-8 BOM으로 되돌리세요. (반대로 `compose/.env`·`compose/compose.yml`은 docker가 읽으므로 BOM 없이 두며, 값은 모두 ASCII·한글은 주석에만 둡니다.)
- 새 로직은 새 스크립트에 하드코딩하지 말고 `scripts/lib/_common.ps1`의 자동 발견/헬퍼(`Get-Instances`, `Get-TargetInstances`, `Invoke-Compose`, `Invoke-Sql` 등)를 재사용하세요.
- 사용자 대면 출력은 한국어이며 `Write-Host -ForegroundColor`로 단계(Cyan 헤더, Green 성공, Yellow 경고, Red 실패, DarkGray 부가)를 구분합니다.
- 배치 작업(`backup.ps1`)은 인스턴스 하나가 실패해도 나머지를 계속 진행하고, 마지막에 요약 표를 낸 뒤 실패가 있으면 `exit 1`을 반환합니다(스케줄러 감지용). 새 배치 스크립트도 이 패턴을 따르세요.
- 릴리스: 하위호환 기능 추가는 마이너 범프 — `CHANGELOG.md`(Keep a Changelog) 갱신 + annotated 태그 `vX.Y.Z` 생성 + `gh release`.
