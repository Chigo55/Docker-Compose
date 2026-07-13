#Requires -Version 5.1
<#
.SYNOPSIS
    컨테이너와 네트워크를 제거합니다. (데이터는 보존됩니다)

.DESCRIPTION
    "정지(stop)"와 "제거(down)"의 차이:
      · stop : 컨테이너를 잠깐 멈춤. 컨테이너는 그대로 남음.
      · down : 컨테이너와 네트워크를 아예 삭제함.

    데이터는 호스트의 바인드 마운트 폴더(DATA_ROOT)에 저장되므로,
    down 을 해도 삭제되지 않습니다. .\scripts\start.ps1 로 다시 올리면
    기존 DB 에 그대로 다시 붙습니다.

.EXAMPLE
    .\scripts\down.ps1
    확인 프롬프트를 거친 뒤 제거합니다.

.EXAMPLE
    .\scripts\down.ps1 -Force
    확인 프롬프트 없이 바로 제거합니다.

.EXAMPLE
    .\scripts\down.ps1 -RemoveImages
    사용하던 이미지까지 함께 삭제합니다.
#>
[CmdletBinding()]
param(
    [switch]$Force,          # 붙이면: "정말요?" 확인 없이 바로 진행
    [switch]$RemoveImages,   # 붙이면: 이미지까지 삭제
    [int]$Timeout = 60       # 정상 종료를 기다리는 시간(초)
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot

Assert-Docker

# 무엇이 지워지는지 먼저 사용자에게 보여 줍니다. (실수 방지)
$instances = Get-Instances
Write-Host "`n다음 컨테이너가 제거됩니다 (데이터는 보존):" -ForegroundColor Yellow
$instances | ForEach-Object { Write-Host ("  - {0}" -f $_.Name) }
Write-Host ("데이터 위치: {0}" -f (Read-DotEnv)['DATA_ROOT']) -ForegroundColor DarkGray

# -Force 가 아니면 사용자에게 한 번 더 확인받습니다.
if (-not $Force) {
    $answer = Read-Host "`n계속하시겠습니까? (y/N)"
    if ($answer -notmatch '^[Yy]$') {
        Write-Host '취소했습니다.' -ForegroundColor DarkGray
        return
    }
}

# docker compose down 인자 조립
$composeArgs = @('down', '--timeout', "$Timeout")
if ($RemoveImages) { $composeArgs += @('--rmi', 'all') }   # 이미지까지 삭제

Write-Host "`n=== 제거 ===" -ForegroundColor Cyan
Invoke-Compose -Arguments $composeArgs

Write-Host "`n제거 완료. 데이터는 그대로 남아 있습니다. 복구: .\scripts\start.ps1" -ForegroundColor Green
