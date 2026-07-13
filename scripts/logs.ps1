#Requires -Version 5.1
<#
.SYNOPSIS
    컨테이너 로그를 봅니다.

.DESCRIPTION
    두 종류의 로그를 볼 수 있습니다.
      · 기본        : docker compose 로그 (컨테이너 표준 출력 — 기동/에러 요약 위주)
      · -ErrorLog   : SQL Server 자체 errorlog (컨테이너 안 /var/opt/mssql/log/errorlog)
                      로그인 실패, DB 복구 상세 등은 이쪽에 남습니다.

.EXAMPLE
    .\scripts\logs.ps1
    전체 컨테이너의 최근 100줄을 봅니다.

.EXAMPLE
    .\scripts\logs.ps1 db2019c -Follow
    db2019c 로그를 실시간으로 따라 봅니다. (Ctrl+C 로 종료)

.EXAMPLE
    .\scripts\logs.ps1 db2022b -Tail 500
    db2022b 의 최근 500줄을 봅니다.

.EXAMPLE
    .\scripts\logs.ps1 db2022e -ErrorLog
    db2022e 의 SQL Server 자체 errorlog 를 봅니다.

.EXAMPLE
    .\scripts\logs.ps1 -Since 30m
    최근 30분치 로그만 봅니다.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Service = @(),   # 첫 번째 위치 인자. 비우면 전체.
    [switch]$Follow,            # 붙이면: 실시간 추적
    [int]$Tail = 100,           # 마지막 몇 줄을 볼지
    [string]$Since,             # 예: '30m', '1h' — 이 시점 이후 로그만
    [switch]$ErrorLog           # 붙이면: SQL Server 자체 errorlog 를 봄
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot

Assert-Docker
$targets = Resolve-Services -Service $Service   # -Service 오타 검증 (빈 배열 = 전체)

# ── (선택) SQL Server 자체 errorlog 보기 ────────────────────────────────────
# docker 로그가 아니라, 컨테이너 안 파일(/var/opt/mssql/log/errorlog)을 직접 읽습니다.
if ($ErrorLog) {
    $instances = Get-TargetInstances -Service $Service   # 대상 인스턴스 목록
    foreach ($instance in $instances) {
        Write-Host ("`n===== {0} : /var/opt/mssql/log/errorlog (마지막 {1}줄) =====" -f $instance.Name, $Tail) -ForegroundColor Cyan
        docker exec $instance.Name tail -n $Tail /var/opt/mssql/log/errorlog
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("  {0} 에서 errorlog 를 읽지 못했습니다 (컨테이너가 실행 중인지 확인)." -f $instance.Name) -ForegroundColor Yellow
        }
    }
    return   # errorlog 만 보고 스크립트를 끝냅니다.
}

# ── 기본: docker compose 로그 보기 ──────────────────────────────────────────
$composeArgs = @('logs', '--tail', "$Tail")
if ($Follow) { $composeArgs += '--follow' }         # 실시간 추적
if ($Since)  { $composeArgs += @('--since', $Since) }  # 특정 시점 이후만
$composeArgs += $targets                             # 대상 지정(없으면 전체)

Invoke-Compose -Arguments $composeArgs
