#Requires -Version 5.1
<#
.SYNOPSIS
    모든 인스턴스의 상태를 표 하나로 보여 줍니다.

.DESCRIPTION
    한 표에 다음 4가지를 모아서 보여 줍니다.
      · State  : 컨테이너가 실행 중인지 (running / 없음 등)
      · Health : 헬스체크 결과 (healthy / unhealthy / starting)
      · TCP    : 호스트 포트로 실제 접속이 되는지 (OK / 응답없음)
      · Data   : 데이터 폴더가 차지하는 용량

.EXAMPLE
    .\scripts\status.ps1
    한 번만 상태를 봅니다.

.EXAMPLE
    .\scripts\status.ps1 -Watch
    5초마다 자동으로 갱신합니다. (Ctrl+C 로 종료)

.EXAMPLE
    .\scripts\status.ps1 -NoSize
    데이터 용량 계산을 생략해 더 빠르게 봅니다.
#>
[CmdletBinding()]
param(
    [switch]$Watch,        # 붙이면: 일정 간격으로 자동 갱신
    [switch]$NoSize,       # 붙이면: 용량 계산 생략 (빠름)
    [int]$Interval = 5     # -Watch 일 때 갱신 간격(초)
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot


# ───────────────────────────────────────────────────────────────────────────
#  Test-TcpPort : 특정 포트로 TCP 접속이 되는지 참/거짓으로 확인합니다.
#  (SQL Server 가 실제로 연결을 받아 주는지 보는 간단한 점검입니다.)
# ───────────────────────────────────────────────────────────────────────────
function Test-TcpPort {
    param(
        [int]$Port,
        [int]$TimeoutMs = 700   # 이 시간 안에 응답이 없으면 실패로 간주
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        # 비동기로 접속을 시도하고, 정해진 시간만큼만 기다립니다.
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()   # 성공하든 실패하든 연결은 항상 닫습니다.
    }
}


# ───────────────────────────────────────────────────────────────────────────
#  Get-DirSizeMB : 폴더 안 모든 파일 용량을 합쳐 MB 단위로 돌려줍니다.
#  폴더가 없으면 $null 을, 비어 있으면 0 을 돌려줍니다.
# ───────────────────────────────────────────────────────────────────────────
function Get-DirSizeMB {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    try {
        $sum = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if (-not $sum) { return 0 }
        return [math]::Round($sum / 1MB, 1)   # 바이트 → MB, 소수점 첫째 자리까지
    } catch {
        return $null
    }
}


# ───────────────────────────────────────────────────────────────────────────
#  Show-Status : 상태 표를 한 번 만들어 화면에 출력합니다.
# ───────────────────────────────────────────────────────────────────────────
function Show-Status {
    Assert-Docker

    # docker ps 로 모든 컨테이너의 이름/상태를 한 번에 가져옵니다.
    # 형식: '이름|상태|상세'  (예: Db2019C|running|Up 3 hours (healthy))
    $raw = docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}'

    # 이름으로 빠르게 찾을 수 있도록 사전(해시테이블)에 담아 둡니다.
    $byName = @{}
    foreach ($line in $raw) {
        $parts = $line -split '\|', 3
        $byName[$parts[0]] = [pscustomobject]@{ State = $parts[1]; Status = $parts[2] }
    }

    # 인스턴스 목록을 돌면서 한 줄씩 표 데이터를 만듭니다.
    $rows = foreach ($instance in (Get-Instances)) {
        $container = $byName[$instance.Name]

        # 컨테이너 실행 상태 (없으면 '(없음)')
        $state = if ($container) { $container.State } else { '(없음)' }

        # 상세 문자열에서 (healthy) 같은 괄호 안 값을 뽑아냅니다.
        $health = '-'
        if ($container -and $container.Status -match '\((healthy|unhealthy|health: starting)\)') {
            $health = $Matches[1]
        }

        # 실행 중일 때만 포트 접속을 확인합니다.
        $tcp = if ($container -and $container.State -eq 'running') {
                   if (Test-TcpPort -Port $instance.Port) { 'OK' } else { '응답없음' }
               } else { '-' }

        # -NoSize 면 용량 계산을 건너뜁니다.
        $size = if ($NoSize) { '-' } else {
                    $mb = Get-DirSizeMB -Path $instance.DataDir
                    if ($null -eq $mb) { 'N/A' } else { "$mb MB" }
                }

        [pscustomobject]@{
            Instance = $instance.Name
            Service  = $instance.Service
            State    = $state
            Health   = $health
            Port     = $instance.Port
            TCP      = $tcp
            Data     = $size
        }
    }

    Write-Host ("`n=== MSSQL Farm 상태  ({0}) ===" -f (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan
    $rows | Format-Table -AutoSize

    # 문제 있는 것만 따로 요약합니다.
    $down = @($rows | Where-Object { $_.State -ne 'running' })
    $sick = @($rows | Where-Object { $_.Health -eq 'unhealthy' })

    if ($down.Count -eq 0 -and $sick.Count -eq 0) {
        Write-Host '모든 인스턴스 정상.' -ForegroundColor Green
    } else {
        if ($down.Count) {
            Write-Host ("미기동: {0}" -f (($down.Instance) -join ', ')) -ForegroundColor Yellow
        }
        if ($sick.Count) {
            Write-Host ("unhealthy: {0}  → .\scripts\logs.ps1 <service> 로 확인" -f (($sick.Instance) -join ', ')) -ForegroundColor Red
        }
    }
}


# ── 실행 ────────────────────────────────────────────────────────────────────
if ($Watch) {
    # -Watch : 화면을 지우고 다시 그리기를 무한 반복합니다.
    while ($true) {
        Clear-Host
        Show-Status
        Write-Host "`n${Interval}초마다 갱신 중... (Ctrl+C 로 종료)" -ForegroundColor DarkGray
        Start-Sleep -Seconds $Interval
    }
} else {
    Show-Status
}
