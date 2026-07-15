#Requires -Version 5.1
<#
.SYNOPSIS
    기동 전에 compose/.env 와 compose.yml 의 규약 위반을 미리 점검합니다.

.DESCRIPTION
    이 저장소는 규약이 여러 개 있고(3종 세트, 서비스 키 일치, 슬래시 경로,
    인라인 주석 금지 등), 한 곳이라도 어긋나면 기동이 조용히 실패합니다.
    이 스크립트는 그런 실수를 "올리기 전에" 찾아 줍니다.

    점검 항목:
      · 필수 전역 키 존재 (프로젝트/이미지/비밀번호/데이터 루트)
      · SA 비밀번호 정책 (8자 이상 + 대/소문자·숫자·기호 중 3종)
      · 인스턴스 3종 세트(_NAME/_PORT/_DIR) 완전성
      · 호스트 포트 중복 및 유효 범위
      · 데이터 폴더(_DIR) 중복 (인스턴스끼리 같은 폴더 공유 위험)
      · .env 접두사 ↔ compose.yml 서비스 키 일치 (양방향)
      · DATA_ROOT 접근 가능 여부
      · 값 옆 인라인 주석 / 역슬래시 경로 등 형식 규약
      · (Docker 가 켜져 있으면) docker compose config 렌더링 성공 여부

    결과는 [OK]/[경고]/[오류] 로 보여 주고, 오류가 하나라도 있으면
    종료 코드 1 을 돌려줍니다(자동화에서 감지용). 경고만 있으면 0 입니다.

.EXAMPLE
    .\scripts\doctor.ps1
    전체 규약을 점검합니다.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot


# ───────────────────────────────────────────────────────────────────────────
#  점검 결과를 모으는 아주 작은 도우미들.
#  · Pass  : 통과한 항목 (초록 [OK])
#  · Warn  : 당장 막지는 않지만 주의할 항목 (노랑 [경고])
#  · Fail  : 기동을 막을 수 있는 항목 (빨강 [오류])
# ───────────────────────────────────────────────────────────────────────────
$script:nWarn = 0
$script:nFail = 0

function Pass { param([string]$Msg) Write-Host ("  [OK]   {0}" -f $Msg) -ForegroundColor Green }
function Warn { param([string]$Msg) Write-Host ("  [경고] {0}" -f $Msg) -ForegroundColor Yellow; $script:nWarn++ }
function Fail { param([string]$Msg) Write-Host ("  [오류] {0}" -f $Msg) -ForegroundColor Red;    $script:nFail++ }

function Show-Section { param([string]$Title) Write-Host ("`n=== {0} ===" -f $Title) -ForegroundColor Cyan }


# ═══════════════════════════════════════════════════════════════════════════
#  0) 파일 존재 확인 — 여기서부터는 .env 가 있다는 전제로 진행합니다.
# ═══════════════════════════════════════════════════════════════════════════
Show-Section '파일'
if (-not (Test-Path $EnvFile)) {
    Fail (".env 가 없습니다: {0}  (.env.example 을 복사해 만드세요)" -f $EnvFile)
    Write-Host "`n점검을 계속할 수 없습니다." -ForegroundColor Red
    exit 1
}
Pass (".env 존재: {0}" -f $EnvFile)

if (-not (Test-Path $ComposeFile)) {
    Fail ("compose.yml 이 없습니다: {0}" -f $ComposeFile)
    exit 1
}
Pass ("compose.yml 존재: {0}" -f $ComposeFile)

$config = Read-DotEnv


# ═══════════════════════════════════════════════════════════════════════════
#  1) 필수 전역 키
# ═══════════════════════════════════════════════════════════════════════════
Show-Section '필수 전역 키'
$requiredKeys = @(
    'COMPOSE_PROJECT_NAME', 'MSSQL_REPO', 'MSSQL_2019_TAG', 'MSSQL_2022_TAG',
    'MSSQL_2019_SQLCMD', 'MSSQL_2022_SQLCMD', 'MSSQL_SA_PASSWORD', 'DATA_ROOT'
)
foreach ($k in $requiredKeys) {
    if ([string]::IsNullOrWhiteSpace($config[$k])) {
        Fail ("{0} 가 비어 있습니다." -f $k)
    } else {
        Pass ("{0}" -f $k)
    }
}


# ═══════════════════════════════════════════════════════════════════════════
#  2) SA 비밀번호 정책 (8자 이상 + 대문자/소문자/숫자/기호 중 3종)
# ═══════════════════════════════════════════════════════════════════════════
Show-Section 'SA 비밀번호'
$pw = $config['MSSQL_SA_PASSWORD']
if ([string]::IsNullOrWhiteSpace($pw)) {
    Fail 'MSSQL_SA_PASSWORD 가 비어 있습니다.'
} else {
    $categories = 0
    if ($pw -cmatch '[A-Z]')            { $categories++ }
    if ($pw -cmatch '[a-z]')            { $categories++ }
    if ($pw -match  '[0-9]')            { $categories++ }
    if ($pw -match  '[^A-Za-z0-9]')     { $categories++ }

    if ($pw.Length -lt 8)   { Fail ("길이가 8자 미만입니다({0}자)." -f $pw.Length) }
    if ($categories -lt 3)  { Fail ("문자 종류가 3종 미만입니다({0}종). 대/소문자·숫자·기호를 섞으세요." -f $categories) }
    if ($pw.Length -ge 8 -and $categories -ge 3) { Pass ("정책 충족 (길이 {0}, 종류 {1})" -f $pw.Length, $categories) }

    # $$ 이스케이프 주의: compose 는 $$→$ 로 해석하지만, 스크립트(Invoke-Sql)는
    # .env 원문을 그대로 씁니다. 값에 $$ 가 있으면 백업/쿼리에서 인증이 어긋날 수 있습니다.
    if ($pw -match '\$\$') {
        Warn '비밀번호에 $$ 가 있습니다. compose 와 스크립트의 $ 해석이 달라 backup/query/restore 인증이 실패할 수 있습니다.'
    }
}


# ═══════════════════════════════════════════════════════════════════════════
#  3) 인스턴스 3종 세트 (_NAME / _PORT / _DIR) 완전성
#     Get-Instances 는 _PORT 로 인스턴스를 발견하므로, _NAME/_DIR 누락을 여기서 봅니다.
# ═══════════════════════════════════════════════════════════════════════════
Show-Section '인스턴스 3종 세트'
$instances = Get-Instances
if (@($instances).Count -eq 0) {
    Fail '인스턴스를 하나도 찾지 못했습니다(_PORT 키 없음).'
} else {
    foreach ($inst in $instances) {
        $prefix = $inst.Service.ToUpper()
        $missing = @()
        if ([string]::IsNullOrWhiteSpace($config["${prefix}_NAME"])) { $missing += "${prefix}_NAME" }
        if ([string]::IsNullOrWhiteSpace($config["${prefix}_DIR"]))  { $missing += "${prefix}_DIR" }
        if ($missing.Count -gt 0) {
            Fail ("{0}: 누락 → {1}" -f $inst.Service, ($missing -join ', '))
        } else {
            Pass ("{0} (name={1}, port={2}, dir={3})" -f $inst.Service, $inst.Name, $inst.Port, (Split-Path $inst.DataDir -Parent | Split-Path -Leaf))
        }
    }
}


# ═══════════════════════════════════════════════════════════════════════════
#  4) 호스트 포트 — 중복 / 유효 범위
# ═══════════════════════════════════════════════════════════════════════════
Show-Section '포트'
$portMap = @{}   # 포트 → [서비스 목록]
foreach ($inst in $instances) {
    $p = $inst.Port
    if ($p -lt 1 -or $p -gt 65535) {
        Fail ("{0}: 포트 값이 유효 범위(1-65535)를 벗어남 → {1}" -f $inst.Service, $p)
        continue
    }
    if (-not $portMap.ContainsKey($p)) { $portMap[$p] = @() }
    $portMap[$p] += $inst.Service
}
$dupPorts = $portMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
if ($dupPorts) {
    foreach ($d in $dupPorts) {
        Fail ("포트 {0} 중복: {1}" -f $d.Key, ($d.Value -join ', '))
    }
} else {
    Pass ("포트 중복 없음 ({0}개 인스턴스)" -f @($instances).Count)
}


# ═══════════════════════════════════════════════════════════════════════════
#  5) 데이터 폴더(_DIR) 중복 — 서로 다른 인스턴스가 같은 폴더를 쓰면 데이터가 섞입니다.
#     (컨테이너명 _NAME 과 폴더명 _DIR 이 다른 것은 정상. 여기선 _DIR 끼리만 봅니다.)
# ═══════════════════════════════════════════════════════════════════════════
Show-Section '데이터 폴더'
$dirMap = @{}
foreach ($inst in $instances) {
    $dir = $config["$($inst.Service.ToUpper())_DIR"]
    if ([string]::IsNullOrWhiteSpace($dir)) { continue }   # 3종 세트 점검에서 이미 잡힘
    $key = $dir.ToLower()
    if (-not $dirMap.ContainsKey($key)) { $dirMap[$key] = @() }
    $dirMap[$key] += $inst.Service
}
$dupDirs = $dirMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
if ($dupDirs) {
    foreach ($d in $dupDirs) {
        Fail ("데이터 폴더 '{0}' 를 여러 인스턴스가 공유: {1}" -f $d.Key, ($d.Value -join ', '))
    }
} else {
    Pass '데이터 폴더 중복 없음'
}


# ═══════════════════════════════════════════════════════════════════════════
#  6) .env 접두사 ↔ compose.yml 서비스 키 일치 (양방향)
#     compose.yml 의 services: 블록에서 2칸 들여쓰기 키만 뽑아 비교합니다.
# ═══════════════════════════════════════════════════════════════════════════
Show-Section '서비스 키 일치'
$composeServices = @()
$inServices = $false
foreach ($line in (Get-Content -Path $ComposeFile -Encoding UTF8)) {
    if ($line -match '^services:\s*$') { $inServices = $true; continue }
    if (-not $inServices) { continue }
    if ($line -match '^[A-Za-z]') { break }                     # networks: 등 다음 최상위 섹션 → 종료
    if ($line -match '^\s*#') { continue }                      # 주석 줄
    if ($line -match '^  ([A-Za-z0-9_.-]+):\s*$') {             # 정확히 2칸 들여쓰기 서비스 키
        $composeServices += $Matches[1].ToLower()
    }
}

$envServices = @($instances | ForEach-Object { $_.Service })
$onlyEnv     = @($envServices     | Where-Object { $_ -notin $composeServices })
$onlyCompose = @($composeServices | Where-Object { $_ -notin $envServices })

if ($onlyEnv.Count -gt 0) {
    Fail (".env 에만 있고 compose.yml 에 없음(그 인스턴스는 기동되지 않음): {0}" -f ($onlyEnv -join ', '))
}
if ($onlyCompose.Count -gt 0) {
    Fail ("compose.yml 에만 있고 .env 에 없음(빈 변수로 기동 실패 위험): {0}" -f ($onlyCompose -join ', '))
}
if ($onlyEnv.Count -eq 0 -and $onlyCompose.Count -eq 0) {
    Pass ("일치 ({0}개 서비스)" -f $composeServices.Count)
}


# ═══════════════════════════════════════════════════════════════════════════
#  7) DATA_ROOT 접근 가능 여부
# ═══════════════════════════════════════════════════════════════════════════
Show-Section 'DATA_ROOT'
$dataRoot = $config['DATA_ROOT']
if ([string]::IsNullOrWhiteSpace($dataRoot)) {
    Fail 'DATA_ROOT 가 비어 있습니다.'
} elseif (Test-Path $dataRoot) {
    Pass ("접근 가능: {0}" -f $dataRoot)
} else {
    Warn ("경로가 아직 없습니다: {0}  (start.ps1 이 인스턴스 폴더를 만들지만, 상위 경로/드라이브는 미리 있어야 합니다)" -f $dataRoot)
}


# ═══════════════════════════════════════════════════════════════════════════
#  8) 형식 규약 — 값 옆 인라인 주석 / 역슬래시 경로
#     Read-DotEnv 는 정리된 값만 주므로, 여기서는 원문 라인을 직접 봅니다.
# ═══════════════════════════════════════════════════════════════════════════
Show-Section '형식 규약'
$formatOk = $true
$lineNo = 0
foreach ($raw in (Get-Content -Path $EnvFile -Encoding UTF8)) {
    $lineNo++
    $trimmed = $raw.Trim()
    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
    $eq = $trimmed.IndexOf('=')
    if ($eq -lt 1) { continue }

    $key   = $trimmed.Substring(0, $eq).Trim()
    $value = $trimmed.Substring($eq + 1)

    # (a) 값 옆 인라인 주석: 값 뒤 "공백 + #". Read-DotEnv 가 주석을 값에 포함시켜 깨뜨립니다.
    if ($value -match '\s#') {
        Fail ("{0}행 {1}: 값 옆 인라인 주석으로 보입니다. 주석은 윗줄에 다세요." -f $lineNo, $key)
        $formatOk = $false
    }

    # (b) 경로 계열 키에 역슬래시: .env 는 Windows 경로도 슬래시(/)를 써야 합니다.
    if ($key -in @('DATA_ROOT', 'BACKUP_ROOT') -and $value -match '\\') {
        Fail ("{0}행 {1}: 역슬래시(\)가 있습니다. .env 에서는 슬래시(/)를 쓰세요." -f $lineNo, $key)
        $formatOk = $false
    }
}
if ($formatOk) { Pass '인라인 주석/경로 형식 규약 통과' }


# ═══════════════════════════════════════════════════════════════════════════
#  9) (Docker 가 켜져 있으면) compose 렌더링 성공 여부
#     .env + compose.yml 을 실제로 합쳐 유효한지 최종 확인합니다.
# ═══════════════════════════════════════════════════════════════════════════
Show-Section 'compose 렌더링'
# docker 명령 자체가 없거나(미설치) 데몬이 꺼져 있어도 여기서 죽지 않고,
# 경고만 남긴 뒤 요약까지 진행합니다. (try/catch 로 CommandNotFound 예외까지 흡수)
$dockerOk = $false
try {
    docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
    $dockerOk = ($LASTEXITCODE -eq 0)
} catch {
    $dockerOk = $false
}

if (-not $dockerOk) {
    Warn 'Docker 에 연결할 수 없어 compose config 검증을 건너뜁니다. (Docker Desktop 실행 후 다시 실행)'
} else {
    & docker compose -f $ComposeFile --env-file $EnvFile config --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Pass 'docker compose config 렌더링 성공'
    } else {
        Fail 'docker compose config 렌더링 실패. 아래 명령으로 상세를 확인하세요:'
        Write-Host '        Push-Location .\compose; docker compose config; Pop-Location' -ForegroundColor DarkGray
    }
}


# ═══════════════════════════════════════════════════════════════════════════
#  요약
# ═══════════════════════════════════════════════════════════════════════════
Write-Host "`n=== 요약 ===" -ForegroundColor Cyan
if ($script:nFail -eq 0 -and $script:nWarn -eq 0) {
    Write-Host '모든 점검 통과. 기동 준비 완료.' -ForegroundColor Green
} else {
    Write-Host ("오류 {0}건 / 경고 {1}건" -f $script:nFail, $script:nWarn) -ForegroundColor $(if ($script:nFail -gt 0) { 'Red' } else { 'Yellow' })
}

if ($script:nFail -gt 0) { exit 1 }   # 오류가 있으면 자동화가 감지할 수 있도록
exit 0                                # 성공: 마지막 외부 명령($LASTEXITCODE, 예: Docker 꺼짐 시 docker info)의 종료코드가 새어나가지 않도록 명시
