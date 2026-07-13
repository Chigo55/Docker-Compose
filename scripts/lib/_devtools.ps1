#Requires -Version 5.1
# ═══════════════════════════════════════════════════════════════════════════
#  _devtools.ps1  —  내부 개발 루프(check.ps1 / test.ps1) 전용 공용 도우미
# ═══════════════════════════════════════════════════════════════════════════
#
#  [이 파일은 직접 실행하지 않습니다]
#  check.ps1 / test.ps1 이 맨 위에서 dot-source 해서 함수들을 가져다 씁니다.
#
#  [왜 _common.ps1 과 분리하나]
#  _common.ps1 은 "운영(ops)" 라이브러리입니다(인스턴스 발견/compose/SQL).
#  이 파일은 "개발 도구"만 다룹니다 — 개발용 모듈(PSScriptAnalyzer/Pester) 확보와
#  파일 변경 감시. 운영 코드에 개발 전용 의존성이 섞이지 않게 일부러 나눴습니다.
# ═══════════════════════════════════════════════════════════════════════════


# ───────────────────────────────────────────────────────────────────────────
#  Get-DevModuleVersion : 설치된 모듈의 "가장 높은 버전"을 돌려줍니다. (없으면 $null)
# ───────────────────────────────────────────────────────────────────────────
function Get-DevModuleVersion {
    param([Parameter(Mandatory)][string]$Name)

    $m = Get-Module -ListAvailable -Name $Name |
         Sort-Object Version -Descending | Select-Object -First 1
    if ($m) { return $m.Version }
    return $null
}


# ───────────────────────────────────────────────────────────────────────────
#  Install-DevModule : 개발용 모듈을 CurrentUser 범위로 설치합니다.
#
#  · 관리자 권한이 필요 없도록 -Scope CurrentUser 로 설치합니다.
#  · 최초 실행 시 NuGet 공급자와 PSGallery 신뢰 설정을 자동으로 준비합니다.
#  · Pester 는 기존 버전(3.4.0) 위에 덮어써야 하므로 -SkipPublisherCheck 를 씁니다.
# ───────────────────────────────────────────────────────────────────────────
function Install-DevModule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [version]$MinimumVersion
    )

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
    }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

    $params = @{ Name = $Name; Scope = 'CurrentUser'; Force = $true; SkipPublisherCheck = $true }
    if ($MinimumVersion) { $params['MinimumVersion'] = $MinimumVersion }
    Install-Module @params
}


# ───────────────────────────────────────────────────────────────────────────
#  Assert-DevModule : 모듈이 요구 버전 이상 있는지 확인합니다.
#
#  · 있으면            → $true
#  · 없고 -Install 이면 → 설치 후 재확인해서 $true/$false
#  · 없고 -Install 아니면 → 노란 안내(설치 방법)를 내고 $false
#
#  Docker 가 꺼져 있을 때 doctor.ps1 이 죽지 않고 경고만 남기는 것과 같은 태도입니다.
#  개발 모듈이 없다고 루프 전체가 멈추면 안 되므로, 그 단계만 건너뛰게 합니다.
# ───────────────────────────────────────────────────────────────────────────
function Assert-DevModule {
    param(
        [Parameter(Mandatory)][string]$Name,
        [version]$MinimumVersion,
        [switch]$Install
    )

    $have = Get-DevModuleVersion -Name $Name
    if ($have -and (-not $MinimumVersion -or $have -ge $MinimumVersion)) { return $true }

    if ($Install) {
        Write-Host ("  {0} 설치 중 (CurrentUser)..." -f $Name) -ForegroundColor DarkGray
        Install-DevModule -Name $Name -MinimumVersion $MinimumVersion
        $have = Get-DevModuleVersion -Name $Name
        return ($have -and (-not $MinimumVersion -or $have -ge $MinimumVersion))
    }

    $req = if ($MinimumVersion) { (" {0} 이상" -f $MinimumVersion) } else { '' }
    Write-Host ("  [건너뜀] {0}{1} 가 없습니다. -Install 로 설치하거나 아래를 직접 실행하세요." -f $Name, $req) -ForegroundColor Yellow
    $verArg = if ($MinimumVersion) { (" -MinimumVersion {0}" -f $MinimumVersion) } else { '' }
    Write-Host ("           Install-Module {0}{1} -Scope CurrentUser" -f $Name, $verArg) -ForegroundColor DarkGray
    return $false
}


# ───────────────────────────────────────────────────────────────────────────
#  Get-WatchStamp : 감시 대상 폴더들의 "현재 상태"를 문자열 하나로 요약합니다.
#
#  각 파일의 전체경로 + 마지막 수정시각(Ticks)을 이어 붙입니다. 이 문자열이
#  이전과 달라지면 무언가 바뀐 것이므로, -Watch 루프가 재실행을 트리거합니다.
#  (FileSystemWatcher 대신 폴링 — status.ps1 -Watch 와 같은 단순 폴링 방식)
# ───────────────────────────────────────────────────────────────────────────
function Get-WatchStamp {
    param([Parameter(Mandatory)][string[]]$Path)

    $items = foreach ($p in $Path) {
        if (Test-Path $p) { Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue }
    }
    ($items | Sort-Object FullName |
        ForEach-Object { '{0}|{1}' -f $_.FullName, $_.LastWriteTimeUtc.Ticks }) -join "`n"
}
