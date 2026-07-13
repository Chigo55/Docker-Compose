# 코드 규약 (CONVENTIONS)

기존 스크립트와 **일관된** 코드를 쓰기 위한 규약이다. 여기 적힌 형태를 그대로 따르면
리뷰 없이도 저장소의 결에 맞는다. 배경은 [ADR](adr/README.md), 안전 가드레일은 [rules](rules/README.md).

## 1. 파일 인코딩

- **`.ps1`은 UTF-8 with BOM**. `compose/.env`·`compose/compose.yml`은 **BOM 없음**([ADR-0012](adr/0012-utf8-bom-for-powershell.md)).
- 주석·사용자 출력은 **한국어**. 코드 식별자, 상태 토큰(`OK`/`FAIL`/`DOWN`), 기술 용어만 영어.

## 2. 스크립트 헤더 (모든 `.ps1`이 이 순서로 시작)

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    한 줄 요약.
.DESCRIPTION
    무엇을 왜 하는지. 위험/전제도 여기에.
.EXAMPLE
    .\scripts\foo.ps1 -Service db2019c
    지정한 인스턴스만 처리합니다.   # 예시마다 명령 + 한국어 한 줄 설명
#>
[CmdletBinding()]
param(
    [switch]$Force,             # 붙이면: 확인 프롬프트를 건너뜀
    [string[]]$Service = @()    # 비우면 전체, 지정하면 그 인스턴스만
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"   # 공용 함수 dot-source
Set-Location -Path $RepoRoot        # _common.ps1 이 계산해 둔 루트

Assert-Docker                        # Docker 를 쓰는 스크립트는 첫 런타임 호출로 점검
```

`.EXAMPLE`은 여러 개 둔다(대표 옵션 조합마다 하나씩).

## 3. 파라미터

- `param()`은 **한 줄에 하나**, 각 줄 끝에 **한국어 인라인 `#` 주석**을 열 맞춰 단다.
- `[switch]` 스위치 주석은 `붙이면: ...` 어투로 통일한다.
- 다중 대상은 `[string[]]$Service = @()`, 주석은 `# 비우면 전체, 지정하면 그 인스턴스만`.
- 위치 인자는 `[Parameter(Position = 0)]`(예: `query.ps1`의 `$Query`, `logs.ps1`의 `$Service`).
- 정수 파라미터는 기본값을 준다(`[int]$Timeout = 60`, `[int]$Interval = 5`, `[int]$Tail = 100`).
- **설정 폴백 규약**: 명령줄 인자가 있으면 그것을, 없으면 `.env` 값을 쓴다.
  ```powershell
  if (-not $Database) { $Database = $config['BACKUP_DATABASE'] }   # (안 주면 .env 값 사용)
  ```

## 4. `_common.ps1` 재사용 (재구현 금지)

| 하려는 일 | 쓸 함수 |
|-----------|---------|
| `.env` 읽기(캐시) | `Read-DotEnv` |
| Docker 켜짐 확인 | `Assert-Docker` |
| 인스턴스 목록(자동 발견) | `Get-Instances` |
| `-Service` 오타 검증(compose 대상 키) | `Resolve-Services` |
| `-Service` 필터된 인스턴스 객체 | `Get-TargetInstances` |
| `docker compose ...` 실행 | `Invoke-Compose` |
| 컨테이너 실행 여부 | `Test-ContainerRunning` |
| 버전별 sqlcmd 경로 | `Get-SqlcmdInvocation` |
| 컨테이너에 T-SQL 실행 | `Invoke-Sql` |

- 인스턴스 객체 속성: `.Service`(소문자 서비스키) / `.Name`(컨테이너명) / `.Port` / `.DataDir`.
- **compose 대상**을 넘길 땐 `Resolve-Services`, **인스턴스 객체**가 필요하면 `Get-TargetInstances`.

## 5. 출력 색상 (의미 고정)

| 색 | 의미 | 형태 |
|----|------|------|
| `Cyan` | 섹션 헤더/배너 | ``"`n=== 제목 ==="`` (인스턴스 소제목은 `===== {name} =====`) |
| `Green` | 성공/정상/완료 | |
| `Yellow` | 경고/비치명적 문제/파괴적 작업 예고 목록 | |
| `Red` | 실패/오류/unhealthy | |
| `DarkGray` | 부가 정보/진행 메모/취소 안내 | `Invoke-Compose`의 `> docker compose ...` 에코도 여기 |

- 헤더 배너는 항상 앞에 개행 `` `n `` 을 두고 제목을 `=== ... ===`로 감싼다.

## 6. 요약 표

- 행은 `[pscustomobject]@{ ... }`로 만들어 `$results` 배열에 모으고, `| Format-Table -AutoSize`로 출력.
- 상태 토큰은 고정: `'OK'` / `'FAIL'` / `'DOWN'`.
- 표 뒤에 실패 요약 한 줄: `$bad = @($results | Where-Object { $_.Result -ne 'OK' })` → 개수 +
  쉼표 결합 인스턴스명을 Red 로.
- `.Count` 전에는 항상 `@(...)`로 감싸 단일 원소 붕괴를 막는다(`@($instances).Count`).

## 7. 종료 코드 / 오류 처리

- 배치에서 하나라도 실패하면 `exit 1`(주석: `# 스케줄러가 실패를 감지할 수 있도록`). 성공은 암묵적 `0`.
- **사용자 취소는 `exit`가 아니라 `return`.**
- 치명적 전제 실패(필수 설정/인자 누락)는 `throw`.
- 외부 명령 실패는 `if ($LASTEXITCODE -ne 0) { throw ... }`로 감지.
- 실행 중 죽은 인스턴스는 `throw` 대신 `DOWN` 기록 후 `continue`(`query.ps1`).

## 8. 배치 부분 실패 패턴

```powershell
$results = @()
foreach ($instance in $instances) {           # 하나 실패해도 나머지는 계속
    $row = [pscustomobject]@{ Instance = $instance.Name; Result = ''; Detail = '' }
    try   { <# 작업 #>; $row.Result = 'OK' }
    catch { $row.Result = 'FAIL'; $row.Detail = $_.Exception.Message
            Write-Host ("  실패: {0}" -f $_.Exception.Message) -ForegroundColor Red }
    $results += $row
}
$results | Format-Table -AutoSize
if (@($results | Where-Object { $_.Result -eq 'FAIL' }).Count -gt 0) { exit 1 }
```

- 임시 자원(스테이징 파일 등)은 `try/finally`로 성공·실패와 무관하게 정리.
- Docker 잡음은 `2>$null | Out-Null`로 억제.

## 9. 파괴적 작업 확인 (`ShouldProcess` 대신 수동 프롬프트)

```powershell
# 1) 영향 목록을 Yellow 로 먼저 보여 준다
Write-Host "삭제 대상:" -ForegroundColor Yellow
# ... 목록 출력 ...
# 2) -Force 가 없으면 y/N 프롬프트
if (-not $Force) {
    $answer = Read-Host "`n계속하시겠습니까? (y/N)"
    if ($answer -notmatch '^[Yy]$') {
        Write-Host '취소했습니다.' -ForegroundColor DarkGray
        return
    }
}
```

- 프롬프트 문구는 ``"`n계속하시겠습니까? (y/N)"``, 정규식은 `^[Yy]$`, 취소 문구는 `'취소했습니다.'`(DarkGray).
- 데이터 보존 작업(`stop`/`restart`)은 파괴적이지 않으므로 프롬프트하지 않는다.

## 10. 실시간(`-Watch` / `-Follow`)

- 네이티브 follow 가 있으면 도구에 위임한다(`logs.ps1 -Follow` → compose 인자에 `--follow` 추가).
- 네이티브가 없으면만 PS 루프(`status.ps1 -Watch`):
  ```powershell
  while ($true) { Clear-Host; Show-Status; Start-Sleep -Seconds $Interval }
  ```
  푸터에 항상 `Ctrl+C 로 종료`를 안내한다.

## 11. 주석 밀도 / 스타일

- 함수마다 박스 헤더 배너(`# ═══...` 또는 `# ─────...`)로 이름과 **평문 목적**을 적는다.
- 인라인 주석은 기계적 설명이 아니라 **의도/이유**를 적는다(예: "성공하든 실패하든 연결은 항상 닫습니다").
- 파일 조직: 작고 응집도 높은 파일 지향. 공통 로직은 `_common.ps1`으로 승격.

## 12. Git 커밋

- 형식: `<type>: <설명>` (type: feat/fix/refactor/docs/test/chore/perf/ci).
- 인스턴스 추가처럼 `.env` 변경이 필요한 작업은 실값 `.env`가 Git 밖이므로, 커밋에는
  `compose.yml`과 `.env.example`만 반영되고 실값은 팀 내 수동 전파임을 유의한다.

## 13. 테스트 / 내부 개발 루프

스크립트/설정을 고칠 때는 편집 후 `.\scripts\check.ps1 -Test`(또는 `-Watch -Test`)로 검증한다.
`check.ps1`(린트 + doctor + compose 렌더링)과 `test.ps1`(Pester)이 루프의 두 축이다.

- **테스트 프레임워크는 Pester 5 이상**을 쓴다(assertion 은 `Should -Be` 대시 문법).
  Windows 기본 Pester 3.4.0 은 문법이 달라 쓰지 않는다. `test.ps1 -Install` 로 부트스트랩.
- 테스트 파일은 `tests\<대상>.Tests.ps1`, `.ps1` 규약(UTF-8 BOM, 한국어)을 그대로 따른다.
- **설정 주입**: `_common.ps1` 의 상태는 `$script:DotEnvCache` 캐시에 있다. 테스트는 이 캐시에
  `[ordered]@{}` 사전을 직접 넣어 파일 없이 `.env` 상태를 흉내 낸다. `Read-DotEnv` 파싱 자체를
  볼 때만 `$TestDrive` 임시 파일을 쓰고, `BeforeEach { $script:DotEnvCache = $null }` 로 캐시를 비운다.
- 기존 동작을 고정하는 **특성 테스트(characterization test)** 를 적극 쓴다. 예: "값 뒤 인라인 주석이
  값에 남는다"는 규약이 인라인 주석을 금지하는 이유를 코드로 못 박는다.
- **개발 모듈(PSScriptAnalyzer/Pester)은 선택 의존성**이다. 없을 때 루프 전체를 멈추지 말고
  해당 단계만 건너뛴다(노란 안내 + `-Install` 힌트). Docker 가 꺼져 있을 때 `doctor.ps1` 이
  경고만 남기고 진행하는 것과 같은 태도다.
- 린트 제외 규칙은 `check.ps1` 상단 `$script:ExcludedRules` 한 곳에서 관리하고, 제외 이유를 주석으로 남긴다.
- 개발 전용 헬퍼는 `scripts/lib/_devtools.ps1` 에 두어 운영 라이브러리(`_common.ps1`)와 분리한다.
