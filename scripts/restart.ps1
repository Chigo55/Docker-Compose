#Requires -Version 5.1
<#
.SYNOPSIS
    컨테이너를 재시작합니다.

.DESCRIPTION
    두 가지 방식이 있습니다.
      · 기본(옵션 없음) : docker compose restart — 컨테이너를 유지한 채 껐다 켜기만 합니다.
                          단, .env 의 포트/이미지/볼륨 변경은 이 방식으로는 반영되지 않습니다.
      · -Recreate      : 컨테이너를 새로 만들어(up --force-recreate) .env 변경분을 반영합니다.

    즉, .env 에서 포트나 이미지 태그를 바꿨다면 반드시 -Recreate 를 써야 합니다.

.EXAMPLE
    .\scripts\restart.ps1
    전체를 단순 재시작합니다. (설정 변경 반영 안 됨)

.EXAMPLE
    .\scripts\restart.ps1 -Service db2022b
    지정한 인스턴스만 재시작합니다.

.EXAMPLE
    .\scripts\restart.ps1 -Recreate
    .env 변경분(포트·이미지·볼륨)을 반영하며 재생성합니다.
#>
[CmdletBinding()]
param(
    [string[]]$Service = @(),   # 비우면 전체, 지정하면 그 인스턴스만
    [switch]$Recreate,          # 붙이면: .env 변경분을 반영하도록 컨테이너를 새로 만듦
    [int]$Timeout = 60          # 정상 종료를 기다리는 시간(초)
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot

Assert-Docker
$targets = Resolve-Services -Service $Service   # -Service 오타 검증 (빈 배열 = 전체)

if ($Recreate) {
    # .env 변경분을 반영하려면 컨테이너를 새로 만들어야 합니다.
    Write-Host "`n=== 재생성 (.env 변경분 반영) ===" -ForegroundColor Cyan
    Invoke-Compose -Arguments (@('up', '-d', '--force-recreate') + $targets)
} else {
    # 단순히 껐다 켜기만 합니다. (설정 변경은 반영되지 않음)
    Write-Host "`n=== 재시작 ===" -ForegroundColor Cyan
    Invoke-Compose -Arguments (@('restart', '--timeout', "$Timeout") + $targets)
}

Write-Host "`n완료. 상태 확인: .\scripts\status.ps1" -ForegroundColor Green
