#Requires -Version 5.1
<#
.SYNOPSIS
    이미지를 "인스턴스 하나씩" 롤링으로 갱신합니다. (무중단에 가깝게)

.DESCRIPTION
    이미지 태그를 올렸을 때 farm 전체를 한꺼번에 내렸다 올리는 대신
    (그러면 farm 이 잠깐 통째로 내려가고, 하나가 잘못돼도 늦게 압니다),
    인스턴스를 하나씩 아래 순서로 갱신하고 다음으로 넘어갑니다.

      1) 이미지 받기        docker compose pull <서비스>     (-NoPull 이면 생략)
      2) 그 서비스만 재생성  docker compose up -d --force-recreate --no-deps <서비스>
      3) healthy 대기        Wait-Healthy (그 인스턴스 하나만, 최대 -Timeout 초)

    한 번에 한 인스턴스만 내려갔다 올라오므로 나머지는 계속 서비스합니다(롤링).

    실패하면 그 지점에서 멈춥니다. 이미 갱신한 인스턴스는 그대로 두고, 아직
    손대지 않은 인스턴스는 건너뜁니다(SKIP). 깨진 이미지를 farm 전체로 퍼뜨리지
    않으려는 의도적인 "실패 시 중단"입니다. 마지막에 요약 표를 내고, 실패가 있으면
    종료 코드 1 을 돌려줍니다(스케줄러가 감지할 수 있도록).

    ※ restart.ps1 -Recreate 는 전체를 동시에 재생성합니다. 무중단이 필요 없고
      빠르게 한꺼번에 반영하려면 그쪽이, 하나씩 확인하며 넘어가려면 이 스크립트가 맞습니다.

.EXAMPLE
    .\scripts\update.ps1
    전체 인스턴스를 하나씩 pull → 재생성 → healthy 확인 순으로 롤링 갱신합니다.

.EXAMPLE
    .\scripts\update.ps1 -Service db2022a,db2022b
    지정한 인스턴스만 롤링 갱신합니다.

.EXAMPLE
    .\scripts\update.ps1 -NoPull
    이미지를 새로 받지 않고, 현재 로컬 이미지로 하나씩 재생성만 합니다.
    (예: .env 변경분을 무중단으로 반영할 때)

.EXAMPLE
    .\scripts\update.ps1 -Timeout 180
    각 인스턴스가 healthy 가 될 때까지 최대 180초 기다립니다(무거운 인스턴스용).
#>
[CmdletBinding()]
param(
    [string[]]$Service = @(),   # 비우면 전체, 지정하면 그 인스턴스만
    [switch]$NoPull,            # 붙이면: 이미지 pull 을 생략하고 현재 로컬 이미지로 재생성만
    [int]$Timeout = 120         # 인스턴스 하나가 healthy 가 될 때까지 최대 대기 시간(초)
)

$ErrorActionPreference = 'Stop'   # 오류가 나면 즉시 멈춤 (사고 방지)

# 공통 함수 모음을 불러옵니다. (Assert-Docker, Get-TargetInstances, Wait-Healthy 등)
. "$PSScriptRoot\lib\_common.ps1"

# 작업 폴더를 저장소 루트로 맞춥니다. ($RepoRoot 는 _common.ps1 이 계산해 둔 값)
Set-Location -Path $RepoRoot


# ═══════════════════════════════════════════════════════════════════════════
#  Update-OneInstance : 인스턴스 "하나"를 갱신하는 실제 절차(pull → 재생성 → healthy).
#  성공하면 조용히 반환하고, 어느 단계든 실패하면 오류(throw)를 냅니다.
#  (성공/실패/건너뜀 집계와 "실패 시 중단"은 아래 메인 반복문이 담당합니다.)
# ═══════════════════════════════════════════════════════════════════════════
function Update-OneInstance {
    param(
        [Parameter(Mandatory)][pscustomobject]$Instance,   # 대상 인스턴스 (Service/Name 사용)
        [Parameter(Mandatory)][int]$TimeoutSec,            # healthy 대기 제한 시간(초)
        [switch]$NoPull                                    # 붙이면 pull 생략
    )

    $svc = $Instance.Service

    # 1) 이미지 받기 (그 서비스 하나만)
    if (-not $NoPull) {
        Write-Host '  이미지 받는 중 (pull)...' -ForegroundColor DarkGray
        Invoke-Compose -Arguments @('pull', $svc)
    }

    # 2) 그 서비스만 재생성. --no-deps 로 다른 서비스는 건드리지 않습니다(롤링 유지).
    Write-Host '  재생성 중 (up --force-recreate)...' -ForegroundColor DarkGray
    Invoke-Compose -Arguments @('up', '-d', '--force-recreate', '--no-deps', $svc)

    # 3) 이 인스턴스가 healthy 가 될 때까지 대기. 시간 안에 못 되면 실패로 봅니다.
    Write-Host ("  healthy 대기 (최대 {0}초)..." -f $TimeoutSec) -ForegroundColor DarkGray
    if (-not (Wait-Healthy -Instances @($Instance) -TimeoutSec $TimeoutSec)) {
        throw ("제한 시간({0}초) 안에 healthy 가 되지 못했습니다." -f $TimeoutSec)
    }
}


# ═══════════════════════════════════════════════════════════════════════════
#  여기서부터 메인 흐름
# ═══════════════════════════════════════════════════════════════════════════

Assert-Docker                                          # Docker 켜져 있는지 확인
# Get-TargetInstances 가 내부에서 Resolve-Services 로 -Service 오타를 검증합니다(빈 배열 = 전체).
$instances = Get-TargetInstances -Service $Service     # 대상 인스턴스 목록 (.env 발견 순서)

Write-Host "`n=== 롤링 업데이트 시작 ===" -ForegroundColor Cyan
Write-Host ("  대상 : {0} 개 인스턴스" -f @($instances).Count)
Write-Host ("  방식 : 하나씩 {0}재생성 → healthy 확인 (최대 {1}초)" -f `
            $(if ($NoPull) { '' } else { 'pull → ' }), $Timeout)
Write-Host '  주의 : 실패하면 그 지점에서 멈추고, 남은 인스턴스는 갱신하지 않습니다.' -ForegroundColor DarkGray

# ── 인스턴스별로 순서대로 갱신 (하나 실패하면 중단, 남은 것은 SKIP) ──────────────
$results       = @()
$stopped       = $false   # 앞 인스턴스가 실패해 이후를 중단해야 하는지
$failedService = ''       # 실패한 인스턴스의 서비스키 (로그 안내에 사용)

$total = @($instances).Count
for ($i = 0; $i -lt $total; $i++) {
    $instance = $instances[$i]

    # 결과 표에 넣을 한 줄. 아래에서 성공/실패/건너뜀에 따라 채웁니다.
    $row = [pscustomobject]@{
        Instance = $instance.Name
        Result   = ''
        Detail   = ''
    }

    # 앞에서 실패했다면 나머지는 손대지 않고 건너뜁니다.
    if ($stopped) {
        $row.Result = 'SKIP'
        $row.Detail = '앞 인스턴스 실패로 중단됨'
        $results += $row
        continue
    }

    Write-Host ("`n--- [{0}/{1}] {2} ---" -f ($i + 1), $total, $instance.Name) -ForegroundColor Cyan
    try {
        Update-OneInstance -Instance $instance -TimeoutSec $Timeout -NoPull:$NoPull
        $row.Result = 'OK'
        Write-Host '  완료: healthy.' -ForegroundColor Green
    }
    catch {
        # 이 인스턴스에서 실패 → 기록하고 이후 인스턴스는 중단합니다(롤링 중단).
        $row.Result    = 'FAIL'
        $row.Detail    = $_.Exception.Message
        $stopped       = $true
        $failedService = $instance.Service
        Write-Host ("  실패: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    $results += $row
}

# ── 요약 ────────────────────────────────────────────────────────────────────
Write-Host "`n=== 업데이트 결과 ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$ok      = @($results | Where-Object { $_.Result -eq 'OK' })
$failed  = @($results | Where-Object { $_.Result -eq 'FAIL' })
$skipped = @($results | Where-Object { $_.Result -eq 'SKIP' })

if ($failed.Count -gt 0) {
    Write-Host ("갱신 {0}개 완료 후 {1} 에서 중단." -f $ok.Count, (($failed.Instance) -join ', ')) -ForegroundColor Red
    if ($skipped.Count -gt 0) {
        Write-Host ("갱신하지 않은 {0}개: {1}" -f $skipped.Count, (($skipped.Instance) -join ', ')) -ForegroundColor Yellow
    }
    Write-Host ("로그 확인: .\scripts\logs.ps1 {0}" -f $failedService) -ForegroundColor DarkGray
    exit 1   # 스케줄러가 실패를 감지할 수 있도록 0 이 아닌 코드로 종료
}

Write-Host ("완료: {0}개 인스턴스를 하나씩 롤링 업데이트했습니다." -f $ok.Count) -ForegroundColor Green
