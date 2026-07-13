#Requires -Version 5.1
<#
.SYNOPSIS
    컨테이너를 정지(멈춤)합니다. 컨테이너 자체는 남겨 둡니다.

.DESCRIPTION
    "정지"와 "제거"는 다릅니다.
      · 정지(stop.ps1)   : 컨테이너를 잠깐 멈춤. 설정/상태 그대로 남음 → start 로 바로 재개.
      · 제거(down.ps1)   : 컨테이너를 아예 지움. (데이터는 호스트에 남지만 컨테이너는 새로 만들어야 함)

    참고: restart:always 정책이라도, 사람이 직접 stop 한 컨테이너는
          Docker 가 마음대로 다시 켜지 않습니다.

.EXAMPLE
    .\scripts\stop.ps1
    전체 인스턴스를 정지합니다.

.EXAMPLE
    .\scripts\stop.ps1 -Service db2019c
    지정한 인스턴스만 정지합니다.
#>
[CmdletBinding()]
param(
    [string[]]$Service = @(),   # 비우면 전체, 지정하면 그 인스턴스만
    [int]$Timeout = 60          # 강제 종료 전 정상 종료를 기다리는 시간(초)
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot

Assert-Docker
$targets = Resolve-Services -Service $Service   # -Service 오타 검증 (빈 배열 = 전체)

Write-Host "`n=== 정지 ===" -ForegroundColor Cyan
Invoke-Compose -Arguments (@('stop', '--timeout', "$Timeout") + $targets)

Write-Host "`n정지 완료. 데이터는 그대로 유지됩니다. 재기동: .\scripts\start.ps1" -ForegroundColor Green
