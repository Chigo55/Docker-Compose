#Requires -Version 5.1
<#
.SYNOPSIS
    같은 T-SQL 을 여러 인스턴스에 한 번에 실행하고 결과를 모아 보여 줍니다.

.DESCRIPTION
    인스턴스가 여러 개인 farm 에서 "전부에 같은 질의"는 일상 작업입니다.
    (버전 확인, DB 목록, 설정 점검 등) 이 스크립트는 컨테이너마다 docker exec 를
    반복하는 수고를 없애고, _common.ps1 의 Invoke-Sql 을 그대로 재사용합니다.

    · 쿼리는 -Query "<문장>" 로 직접 주거나, -File <경로.sql> 로 파일에서 읽습니다.
    · -Service 로 대상을 좁힐 수 있고, 비우면 전체 인스턴스가 대상입니다.
    · 한 인스턴스가 실패해도 나머지는 계속 실행하고, 마지막에 요약을 냅니다.
      실패가 하나라도 있으면 종료 코드 1 을 돌려줍니다(스케줄러 감지용).

    ※ 읽기 쿼리에 권장합니다. 데이터를 바꾸는 문장(UPDATE/DROP 등)도 실행되므로,
      전체 대상으로 파괴적 쿼리를 돌릴 때는 -Service 로 범위를 좁히세요.

.EXAMPLE
    .\scripts\query.ps1 "SELECT @@VERSION"
    모든 인스턴스의 버전을 확인합니다.

.EXAMPLE
    .\scripts\query.ps1 "SELECT name FROM sys.databases ORDER BY name" -Service db2019c
    db2019c 의 DB 목록을 봅니다.

.EXAMPLE
    .\scripts\query.ps1 -File .\scripts\sql\health.sql
    파일에 담긴 T-SQL 을 전체 인스턴스에 실행합니다.

.EXAMPLE
    .\scripts\query.ps1 "SELECT COUNT(*) FROM dbo.Orders" -Database MyDb -Service db2022a,db2022b
    지정한 DB/인스턴스에 대해 실행합니다.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Query,               # 실행할 T-SQL (또는 -File 로 대체)
    [string]$File,                # .sql 파일 경로 (-Query 대신)
    [string[]]$Service = @(),     # 비우면 전체, 지정하면 그 인스턴스만
    [string]$Database = 'master', # 접속할 DB (기본: master)
    [int]$LoginTimeout = 10       # 로그인 대기 시간(초)
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot

Assert-Docker

# ── 쿼리 원문 결정: -File 이 있으면 파일에서, 아니면 -Query 에서 ────────────────
if ($File) {
    if (-not (Test-Path $File)) { throw ("SQL 파일을 찾을 수 없습니다: {0}" -f $File) }
    $Query = Get-Content -Path $File -Raw -Encoding UTF8
}
if ([string]::IsNullOrWhiteSpace($Query)) {
    throw '실행할 쿼리가 없습니다. -Query "<문장>" 또는 -File <경로.sql> 를 지정하세요.'
}

# 대상 인스턴스 목록
$instances = Get-TargetInstances -Service $Service

Write-Host "`n=== 쿼리 실행 ===" -ForegroundColor Cyan
Write-Host ("  대상 : {0} 개 인스턴스 / DB: {1}" -f @($instances).Count, $Database) -ForegroundColor DarkGray

# ── 인스턴스별로 실행 (하나 실패해도 나머지는 계속) ──────────────────────────
$results = @()
foreach ($instance in $instances) {
    $row = [pscustomobject]@{
        Instance = $instance.Name
        Result   = ''
    }

    Write-Host ("`n===== {0} ({1}) =====" -f $instance.Name, $instance.Service) -ForegroundColor Cyan

    # 컨테이너가 꺼져 있으면 곧장 실패로 기록하고 넘어갑니다.
    if (-not (Test-ContainerRunning -Container $instance.Name)) {
        Write-Host '  (실행 중이 아님)' -ForegroundColor Yellow
        $row.Result = 'DOWN'
        $results += $row
        continue
    }

    $res = Invoke-Sql -Container $instance.Name -Query $Query -Database $Database -LoginTimeout $LoginTimeout

    if ($res.Success) {
        # 출력이 없으면(예: SET/DDL) 빈 줄 대신 안내를 보여 줍니다.
        if ([string]::IsNullOrWhiteSpace($res.Output)) {
            Write-Host '  (출력 없음)' -ForegroundColor DarkGray
        } else {
            Write-Host $res.Output
        }
        $row.Result = 'OK'
    } else {
        Write-Host ("  실패: {0}" -f $res.Output) -ForegroundColor Red
        $row.Result = 'FAIL'
    }

    $results += $row
}

# ── 요약 ────────────────────────────────────────────────────────────────────
Write-Host "`n=== 실행 결과 ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$bad = @($results | Where-Object { $_.Result -ne 'OK' })
if ($bad.Count -gt 0) {
    Write-Host ("성공하지 못함 {0}건: {1}" -f $bad.Count, (($bad.Instance) -join ', ')) -ForegroundColor Red
    exit 1   # 스케줄러가 실패를 감지할 수 있도록 0 이 아닌 코드로 종료
}

Write-Host ("전체 {0}건 실행 성공." -f @($results).Count) -ForegroundColor Green
