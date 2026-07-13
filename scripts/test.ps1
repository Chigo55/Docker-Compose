#Requires -Version 5.1
<#
.SYNOPSIS
    Pester 단위 테스트를 실행합니다. (내부 개발 루프의 테스트 단계)

.DESCRIPTION
    tests\ 폴더의 *.Tests.ps1 을 Pester 로 실행합니다. 주로 _common.ps1 의
    자동 발견/파싱 로직(Read-DotEnv / Get-Instances / Resolve-Services)을 검증합니다.

    Pester 5 이상이 필요합니다. 한국어 Windows 에 기본 설치된 Pester 3.4.0 은 문법이
    달라 쓰지 않습니다. 없으면 -Install 로 CurrentUser 범위에 설치할 수 있습니다.

    실패한 테스트가 있으면 종료 코드 1 을 돌려줍니다(자동화/CI 감지용).

.EXAMPLE
    .\scripts\test.ps1
    tests\ 의 모든 단위 테스트를 실행합니다.

.EXAMPLE
    .\scripts\test.ps1 -Install
    Pester 5+ 가 없으면 설치한 뒤 실행합니다.

.EXAMPLE
    .\scripts\test.ps1 -Path .\tests\_common.Tests.ps1
    특정 테스트 파일만 실행합니다.
#>
[CmdletBinding()]
param(
    [switch]$Install,   # 붙이면: Pester 5+ 가 없으면 CurrentUser 로 설치
    [string]$Path       # 특정 테스트 파일/폴더 (안 주면 tests\ 전체)
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
. "$PSScriptRoot\lib\_devtools.ps1"
Set-Location -Path $RepoRoot

Write-Host "`n=== 단위 테스트 (Pester) ===" -ForegroundColor Cyan

if (-not (Assert-DevModule -Name Pester -MinimumVersion '5.0' -Install:$Install)) {
    Write-Host '  Pester 5 이상이 필요합니다. .\scripts\test.ps1 -Install 로 설치하세요.' -ForegroundColor Yellow
    exit 1
}
Import-Module Pester -MinimumVersion '5.0'

if (-not $Path) { $Path = Join-Path $RepoRoot 'tests' }

# Pester 5+ 의 설정 기반 API. (New-PesterConfiguration → Invoke-Pester -Configuration)
$config = New-PesterConfiguration
$config.Run.Path        = $Path
$config.Run.PassThru    = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config

Write-Host ("`n통과 {0} / 실패 {1} / 건너뜀 {2}" -f `
        $result.PassedCount, $result.FailedCount, $result.SkippedCount) `
    -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })

if ($result.FailedCount -gt 0) { exit 1 }   # 자동화/CI 가 실패를 감지할 수 있도록
