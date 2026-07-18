#Requires -Version 5.1
<#
.SYNOPSIS
    인스턴스별 DB 인벤토리를 한 표로 보여 줍니다. (읽기 전용)

.DESCRIPTION
    "어느 인스턴스에 어떤 DB 가, 얼마나 크게, 어떤 복구 모델로 있고, 마지막 전체 백업이
    언제였는지"를 한눈에 봅니다. 백업 대상 파악과 용량 계획에 필요한 정보를 모읍니다.

    각 인스턴스에 접속해 다음을 조인해 DB 한 줄로 만듭니다.
      · sys.databases    : 이름 · 상태(state_desc) · 복구 모델(recovery_model_desc)
      · sys.master_files : 데이터(ROWS)/로그(LOG) 파일 크기 (8KB 페이지 → MB)
      · msdb..backupset  : 가장 최근 "전체(Full)" 백업의 완료 시각 (type = 'D')

    아무것도 바꾸지 않는 조회 전용입니다. _common.ps1 의 헬퍼(Get-TargetInstances,
    Invoke-Sql -Separator '|')만 재사용하며 새 함수를 두지 않습니다.

    기본은 사용자 DB 만 보여 줍니다(시스템 DB master/tempdb/model/msdb 제외).
    -IncludeSystem 을 주면 시스템 DB 도 포함합니다. -Database 로 이름을 주면 그 DB 가
    어느 인스턴스에 있는지만 추립니다(이때는 시스템/사용자 구분 없이 이름으로 찾습니다).

    최근 백업은 "전체(Full)" 백업의 최신 완료 시각입니다. 전체 백업이 복구의 기준선이라
    "이 DB 가 최근에 백업됐는가" 판단에 가장 의미 있어 이 값을 씁니다(차등/로그는 제외).

    실행 중이 아닌 인스턴스는 조회할 수 없어 DOWN 으로, 조회에 실패하면 FAIL 로 표시하고
    나머지는 계속 진행합니다. 하나라도 OK 가 아니면 종료 코드 1 을 돌려줍니다(스케줄러 감지용).

.EXAMPLE
    .\scripts\databases.ps1
    전체 인스턴스의 사용자 DB 인벤토리를 봅니다.

.EXAMPLE
    .\scripts\databases.ps1 -Service db2019c
    db2019c 인스턴스의 DB 만 봅니다.

.EXAMPLE
    .\scripts\databases.ps1 -Database MyDb
    MyDb 가 어느 인스턴스에 있는지(크기·복구 모델·최근 백업과 함께) 찾습니다.

.EXAMPLE
    .\scripts\databases.ps1 -IncludeSystem
    시스템 DB(master/tempdb/model/msdb)까지 포함해 봅니다.
#>
[CmdletBinding()]
param(
    [string[]]$Service = @(),     # 비우면 전체, 지정하면 그 인스턴스만
    [string]$Database,            # 값을 주면: 그 이름의 DB 만 추려 어느 인스턴스에 있는지 확인
    [switch]$IncludeSystem        # 붙이면: 시스템 DB(master/tempdb/model/msdb)도 포함
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot

Assert-Docker

# ── 조회 대상 인스턴스 ────────────────────────────────────────────────────────
$instances = Get-TargetInstances -Service $Service

# ── DB 인벤토리 쿼리 ──────────────────────────────────────────────────────────
#  · 데이터/로그 크기는 sys.master_files 의 size(8KB 페이지)를 유형별로 합산합니다.
#  · 최근 백업은 msdb..backupset 에서 "전체(Full, type='D')" 백업의 최신 완료 시각입니다.
#  · 백업 이력이 없으면 서브쿼리가 NULL → ISNULL 로 빈 문자열로 만들어 아래에서 '(없음)' 처리.
#  · WHERE 절은 옵션에 따라 달라집니다:
#      -Database → 그 이름만 / (기본) → 시스템 DB(database_id 1~4) 제외 / -IncludeSystem → 전체
$where = if ($Database) {
    "WHERE d.name = N'$Database'"
} elseif ($IncludeSystem) {
    ''
} else {
    'WHERE d.database_id > 4'
}

$dbQuery = @"
SET NOCOUNT ON;
SELECT d.name,
       d.state_desc,
       d.recovery_model_desc,
       CAST(ISNULL(SUM(CASE WHEN mf.type_desc = 'ROWS' THEN mf.size END), 0) * 8.0 / 1024 AS DECIMAL(18,1)),
       CAST(ISNULL(SUM(CASE WHEN mf.type_desc = 'LOG'  THEN mf.size END), 0) * 8.0 / 1024 AS DECIMAL(18,1)),
       ISNULL((SELECT CONVERT(VARCHAR(19), MAX(b.backup_finish_date), 120)
               FROM msdb.dbo.backupset b
               WHERE b.database_name = d.name AND b.type = 'D'), '')
FROM sys.databases d
LEFT JOIN sys.master_files mf ON mf.database_id = d.database_id
$where
GROUP BY d.name, d.state_desc, d.recovery_model_desc
ORDER BY d.name;
"@

Write-Host "`n=== DB 인벤토리 ===" -ForegroundColor Cyan
Write-Host ("  대상 : {0} 개 인스턴스" -f @($instances).Count) -ForegroundColor DarkGray
if ($Database) {
    Write-Host ("  DB 필터 : {0}" -f $Database) -ForegroundColor DarkGray
} else {
    $scope = if ($IncludeSystem) { '시스템 DB 포함' } else { '사용자 DB 만 (시스템 DB 제외)' }
    Write-Host ("  범위 : {0}" -f $scope) -ForegroundColor DarkGray
}

# ── 인스턴스별로 조회 (하나 실패해도 나머지는 계속) ──────────────────────────
$results = @()   # 인스턴스별 처리 결과(요약·종료 코드용)
$dbRows  = @()   # 전체 인벤토리 표 (한 DB = 한 줄)
foreach ($instance in $instances) {
    $row = [pscustomobject]@{ Instance = $instance.Name; Result = ''; DBs = 0 }

    # 꺼진 인스턴스는 조회할 수 없으므로 DOWN 으로 기록하고 넘어갑니다.
    if (-not (Test-ContainerRunning -Container $instance.Name)) {
        Write-Host ("  {0}: 실행 중이 아님 (건너뜀)" -f $instance.Name) -ForegroundColor Yellow
        $row.Result = 'DOWN'
        $results += $row
        continue
    }

    $res = Invoke-Sql -Container $instance.Name -Separator '|' -Query $dbQuery
    if (-not $res.Success) {
        Write-Host ("  {0}: 조회 실패 - {1}" -f $instance.Name, $res.Output) -ForegroundColor Red
        $row.Result = 'FAIL'
        $results += $row
        continue
    }

    # '|' 로 구분된 여러 컬럼을 나눠 한 줄씩 표 행으로 만듭니다(report.ps1 과 같은 방식).
    $count = 0
    foreach ($line in ($res.Output -split "`n")) {
        if ($line -notmatch '\|') { continue }
        $c = $line -split '\|'
        if ($c.Count -lt 6) { continue }

        $last = $c[5].Trim()
        if (-not $last) { $last = '(없음)' }   # 전체 백업 이력이 없는 DB

        $dbRows += [pscustomobject]@{
            Instance   = $instance.Name
            DB         = $c[0].Trim()
            '상태'     = $c[1].Trim()
            '복구모델' = $c[2].Trim()
            '데이터MB' = $c[3].Trim()
            '로그MB'   = $c[4].Trim()
            '최근백업' = $last
        }
        $count++
    }
    $row.Result = 'OK'
    $row.DBs    = $count
    $results += $row
}

# ── 인벤토리 표 ──────────────────────────────────────────────────────────────
if (@($dbRows).Count -gt 0) {
    $dbRows | Format-Table -AutoSize
} else {
    $msg = if ($Database) {
        "'{0}' 이름의 DB 를 찾지 못했습니다." -f $Database
    } else {
        '표시할 DB 가 없습니다.'
    }
    Write-Host ("  {0}" -f $msg) -ForegroundColor Yellow
}

# ── 요약 ────────────────────────────────────────────────────────────────────
Write-Host "`n=== 요약 ===" -ForegroundColor Cyan
$okList = @($results | Where-Object { $_.Result -eq 'OK' })
Write-Host ("  DB 합계 : {0} 개 ({1} 개 인스턴스 조회 성공)" -f @($dbRows).Count, $okList.Count) -ForegroundColor DarkGray

$bad = @($results | Where-Object { $_.Result -ne 'OK' })
if ($bad.Count -gt 0) {
    $down = @($bad | Where-Object { $_.Result -eq 'DOWN' })
    $fail = @($bad | Where-Object { $_.Result -eq 'FAIL' })
    if ($down.Count -gt 0) {
        Write-Host ("미기동 {0}건: {1}" -f $down.Count, (($down.Instance) -join ', ')) -ForegroundColor Yellow
    }
    if ($fail.Count -gt 0) {
        Write-Host ("조회 실패 {0}건: {1}" -f $fail.Count, (($fail.Instance) -join ', ')) -ForegroundColor Red
    }
    exit 1   # 스케줄러가 문제를 감지할 수 있도록 0 이 아닌 코드로 종료
}

Write-Host ("전체 {0}개 인스턴스 조회 성공." -f @($results).Count) -ForegroundColor Green
