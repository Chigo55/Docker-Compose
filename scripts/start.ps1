#Requires -Version 5.1
<#
.SYNOPSIS
    SQL Server 컨테이너들을 기동(시작)합니다. 데이터 폴더도 자동으로 만들어 줍니다.

.DESCRIPTION
    이 스크립트가 하는 일은 두 단계입니다.
      1) 각 인스턴스의 데이터 폴더가 있는지 확인하고, 없으면 먼저 만듭니다.
         (폴더가 없는 채로 기동하면 Docker 가 빈 폴더를 만들어 버려서
          기존 DB 를 못 붙는 사고가 납니다. 그래서 반드시 먼저 만듭니다.)
      2) docker compose up -d 로 컨테이너를 백그라운드에서 띄웁니다.

.EXAMPLE
    .\scripts\start.ps1
    전체 인스턴스를 기동합니다.

.EXAMPLE
    .\scripts\start.ps1 -Pull
    이미지 최신본을 먼저 받은 뒤 기동합니다.

.EXAMPLE
    .\scripts\start.ps1 -Recreate
    컨테이너를 강제로 새로 만들어 기동합니다.

.EXAMPLE
    .\scripts\start.ps1 -Service db2019c,db2022e
    지정한 인스턴스만 기동합니다.

.EXAMPLE
    .\scripts\start.ps1 -Pull -Wait -Timeout 120
    이미지 최신본을 받아 기동한 뒤, 전 인스턴스가 healthy 가 될 때까지(최대 120초) 대기합니다.
    무인 자동화(스케줄러·CI)에서 "기동이 실제로 끝났는지"를 확실히 알 수 있습니다.
#>
[CmdletBinding()]
param(
    [switch]$Pull,              # 붙이면: 이미지 최신본을 먼저 내려받음
    [switch]$Recreate,          # 붙이면: 컨테이너를 강제로 새로 만듦
    [switch]$Wait,              # 붙이면: 전 인스턴스가 healthy 가 될 때까지 대기(무인 자동화용)
    [int]$Timeout = 120,        # -Wait 일 때 최대 대기 시간(초)
    [string[]]$Service = @()    # 비우면 전체, 지정하면 그 인스턴스만
)

$ErrorActionPreference = 'Stop'   # 오류가 나면 즉시 멈춤 (사고 방지)

# 공통 함수 모음을 불러옵니다. (Assert-Docker, Get-TargetInstances 등)
. "$PSScriptRoot\lib\_common.ps1"

# 작업 폴더를 저장소 루트로 맞춥니다. ($RepoRoot 는 _common.ps1 이 계산해 둔 값)
Set-Location -Path $RepoRoot

# ── 0) 준비 ────────────────────────────────────────────────────────────────
Assert-Docker                                          # Docker 켜져 있는지 확인
$targets   = Resolve-Services -Service $Service        # -Service 오타 검증 (빈 배열 = 전체)
$instances = Get-TargetInstances -Service $Service     # 대상 인스턴스 목록

# ── 1) 데이터 디렉터리 준비 ─────────────────────────────────────────────────
# 폴더가 없으면 Docker 가 빈 폴더를 만들어 기존 DB 를 못 찾습니다. 먼저 확인/생성합니다.
# MOUNT_LOG_SECRETS=true 면 errorlog·secrets 마운트용 폴더도 함께 만듭니다.
# (compose.yml 각 서비스 volumes 의 log/secrets 주석도 함께 지워야 실제로 마운트됩니다.)
$mountLogSecrets = ("$((Read-DotEnv)['MOUNT_LOG_SECRETS'])".Trim() -match '^(?i:true|1|yes)$')

Write-Host "`n=== 데이터 디렉터리 ===" -ForegroundColor Cyan
if ($mountLogSecrets) {
    Write-Host '  MOUNT_LOG_SECRETS=true → log/secrets 폴더도 준비합니다.' -ForegroundColor DarkGray
}
foreach ($instance in $instances) {
    # 항상 data. 옵션이 켜져 있으면 같은 인스턴스 폴더 아래 log/secrets 도 함께.
    $needed = [System.Collections.Generic.List[string]]::new()
    $needed.Add($instance.DataDir)
    if ($mountLogSecrets) {
        $instanceRoot = Split-Path $instance.DataDir -Parent   # DATA_ROOT/<_DIR> (data 의 부모)
        $needed.Add((Join-Path $instanceRoot 'log'))
        $needed.Add((Join-Path $instanceRoot 'secrets'))
    }

    foreach ($dir in $needed) {
        if (Test-Path $dir) {
            Write-Host ("  [있음]   {0}" -f $dir) -ForegroundColor DarkGray
        } else {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host ("  [생성함] {0}" -f $dir) -ForegroundColor Yellow
        }
    }
}

# ── 2) 기동 ────────────────────────────────────────────────────────────────
# docker compose 에 넘길 인자들을 상황에 맞게 조립합니다.
$composeArgs = @('up', '-d')                            # -d : 백그라운드 실행
if ($Pull)     { $composeArgs += @('--pull', 'always') }
if ($Recreate) { $composeArgs += '--force-recreate' }
$composeArgs += $targets                                # 대상 지정(없으면 전체)

Write-Host "`n=== 기동 ===" -ForegroundColor Cyan
Invoke-Compose -Arguments $composeArgs

# ── 3) (선택) healthy 대기 ───────────────────────────────────────────────────
# -Wait 면 임의의 Start-Sleep 대신 각 컨테이너의 헬스 상태를 폴링해 실제로 기다립니다.
if ($Wait) {
    Write-Host "`n=== healthy 대기 (최대 ${Timeout}초) ===" -ForegroundColor Cyan
    if (-not (Wait-Healthy -Instances $instances -TimeoutSec $Timeout)) {
        Write-Host "`n일부 인스턴스가 제한 시간 안에 healthy 가 되지 못했습니다. .\scripts\logs.ps1 <service> 로 확인하세요." -ForegroundColor Red
        exit 1   # 스케줄러/CI 가 실패를 감지할 수 있도록
    }
    Write-Host "`n기동 완료. 전 인스턴스 healthy." -ForegroundColor Green
} else {
    Write-Host "`n기동 완료. 상태 확인: .\scripts\status.ps1  (healthy 까지 30~60초 걸립니다)" -ForegroundColor Green
}
