#Requires -Version 5.1
<#
.SYNOPSIS
    전 인스턴스의 sa 비밀번호를 회전(변경)하고 compose/.env 를 함께 갱신합니다.

.DESCRIPTION
    모든 인스턴스는 .env 의 MSSQL_SA_PASSWORD 하나를 공유합니다. 따라서 회전은
    farm 전체에 대해 "모두 성공 or 모두 원복"으로만 처리합니다. 일부만 바뀌면 .env 와
    어긋나 backup/query/restore 인증이 조용히 깨지기 때문입니다.

    절차:
      1) 전제 점검 — 모든 인스턴스가 실행 중이어야 함(하나라도 내려 있으면 중단).
      2) 새 비밀번호 결정 — -Generate(무작위) 또는 프롬프트 입력(두 번 확인).
         정책 검증(8자 이상 + 대/소문자·숫자·기호 중 3종 이상) + 금지 문자 검사.
      3) .env 백업 — compose/.env.bak.<시각> 로 원본을 남깁니다.
      4) 순방향 — 각 인스턴스에 (이전 비밀번호로 접속) ALTER LOGIN [sa] 새 비밀번호 적용.
      5) 하나라도 실패하면 롤백 — 이미 바꾼 인스턴스를 (새 비밀번호로 접속) 이전 값으로
         되돌립니다. .env 는 건드리지 않습니다.
      6) 전부 성공하면 .env 의 MSSQL_SA_PASSWORD 를 새 값으로 갱신합니다.

    금지 문자: $ " \ ` — compose 변수 확장이나 헬스체크 셸 인용과 충돌합니다.

    ※ 되돌리기 어려운 farm 전체 작업입니다. -Force 가 없으면 먼저 확인합니다.
      실제 환경에 쓰기 전 반드시 테스트 환경에서 검증하세요.

.EXAMPLE
    .\scripts\rotate-password.ps1
    새 비밀번호를 두 번 입력받아 전 인스턴스에 적용하고 .env 를 갱신합니다.

.EXAMPLE
    .\scripts\rotate-password.ps1 -Generate
    정책을 충족하는 무작위 비밀번호를 생성해 회전합니다(생성값을 마지막에 출력).
#>
[CmdletBinding()]
param(
    [switch]$Generate,          # 붙이면: 정책 충족 무작위 비밀번호를 생성
    [int]$Length = 20,          # -Generate 시 생성 길이 (최소 12 로 보정)
    [switch]$Force              # 붙이면: 확인 프롬프트를 건너뜀
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot


# ───────────────────────────────────────────────────────────────────────────
#  Test-PasswordPolicy : SA 비밀번호 정책을 검사합니다.
#  통과하면 $null, 위반하면 사람이 읽는 오류 메시지를 돌려줍니다.
#    · 8자 이상 + 대문자/소문자/숫자/기호 중 3종 이상 (doctor.ps1 과 같은 규칙)
#    · 금지 문자($ " \ `) 없음 — compose 변수 확장/헬스체크 셸 인용과 충돌하므로
# ───────────────────────────────────────────────────────────────────────────
function Test-PasswordPolicy {
    param([Parameter(Mandatory)][string]$Password)

    if ($Password.Length -lt 8) { return ("길이가 8자 미만입니다({0}자)." -f $Password.Length) }

    $categories = 0
    if ($Password -cmatch '[A-Z]')        { $categories++ }
    if ($Password -cmatch '[a-z]')        { $categories++ }
    if ($Password -match  '[0-9]')        { $categories++ }
    if ($Password -match  '[^A-Za-z0-9]') { $categories++ }
    if ($categories -lt 3) { return ("문자 종류가 3종 미만입니다({0}종). 대/소문자·숫자·기호를 섞으세요." -f $categories) }

    if ($Password -match '[\$"\\`]') { return '금지 문자($ " \ `)가 있습니다. compose 변수 확장/헬스체크와 충돌합니다.' }

    return $null
}


# ───────────────────────────────────────────────────────────────────────────
#  New-RotatedPassword : 정책을 확실히 충족하는 무작위 비밀번호를 만듭니다.
#  대/소문자·숫자·안전 기호를 각각 하나씩 넣고 나머지를 무작위로 채운 뒤 섞습니다.
#  기호 집합은 금지 문자($ " \ `)를 뺀 안전한 것만 씁니다.
# ───────────────────────────────────────────────────────────────────────────
function New-RotatedPassword {
    param([int]$Length = 20)

    $upper = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $lower = [char[]]'abcdefghijklmnopqrstuvwxyz'
    $digit = [char[]]'0123456789'
    $sym   = [char[]]'!#%^&*()-_=+'
    $all   = $upper + $lower + $digit + $sym

    if ($Length -lt 12) { $Length = 12 }

    # 각 종류 하나씩 먼저 확보(정책 보장), 나머지는 전체에서 무작위로.
    $chars = New-Object System.Collections.Generic.List[char]
    $chars.Add(($upper | Get-Random))
    $chars.Add(($lower | Get-Random))
    $chars.Add(($digit | Get-Random))
    $chars.Add(($sym   | Get-Random))
    for ($i = $chars.Count; $i -lt $Length; $i++) { $chars.Add(($all | Get-Random)) }

    # 앞자리가 항상 대문자가 되지 않도록 순서를 섞습니다.
    return -join ($chars | Sort-Object { Get-Random })
}


# ───────────────────────────────────────────────────────────────────────────
#  Read-NewPassword : 새 비밀번호를 두 번 입력받아 일치하면 평문으로 돌려줍니다.
#  (.env 가 평문이라 최종 저장은 평문이지만, 입력 중에는 화면에 남기지 않습니다.)
# ───────────────────────────────────────────────────────────────────────────
function Read-NewPassword {
    $s1 = Read-Host '새 sa 비밀번호' -AsSecureString
    $s2 = Read-Host '새 sa 비밀번호(확인)' -AsSecureString

    $p1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
    $p2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))

    if ($p1 -cne $p2) { throw '두 입력이 일치하지 않습니다.' }
    return $p1
}


# ═══════════════════════════════════════════════════════════════════════════
#  여기서부터 메인 흐름
# ═══════════════════════════════════════════════════════════════════════════

Assert-Docker
$config = Read-DotEnv

$oldPw = $config['MSSQL_SA_PASSWORD']
if ([string]::IsNullOrEmpty($oldPw)) {
    throw '.env 에 MSSQL_SA_PASSWORD 가 없습니다. 회전하려면 현재 비밀번호가 필요합니다.'
}

# 회전은 farm 전체 대상입니다(공유 비밀번호이므로 부분 회전 불가).
$instances = Get-Instances
if (@($instances).Count -eq 0) { throw '인스턴스를 하나도 찾지 못했습니다.' }

# 전제: 모든 인스턴스가 실행 중이어야 합니다(내려 있으면 부분 회전 → .env 와 어긋남).
$down = @($instances | Where-Object { -not (Test-ContainerRunning -Container $_.Name) })
if ($down.Count -gt 0) {
    throw ("실행 중이 아닌 인스턴스가 있습니다: {0}`n회전은 전 인스턴스가 켜져 있을 때만 안전합니다(.start.ps1 로 먼저 기동)." -f (($down.Name) -join ', '))
}

# 새 비밀번호 결정
if ($Generate) {
    $newPw = New-RotatedPassword -Length $Length
} else {
    $newPw = Read-NewPassword
}

$policyError = Test-PasswordPolicy -Password $newPw
if ($policyError) { throw ("새 비밀번호가 정책을 위반합니다: {0}" -f $policyError) }
if ($newPw -ceq $oldPw) { throw '새 비밀번호가 기존과 같습니다. 다른 값을 쓰세요.' }

# ── 파괴적(farm 전체) 작업 확인 ──────────────────────────────────────────────
Write-Host "`n=== sa 비밀번호 회전 ===" -ForegroundColor Cyan
Write-Host ("  대상: {0} 개 인스턴스 (전체)" -f @($instances).Count)
Write-Host "`n전 인스턴스의 sa 비밀번호를 바꾸고 .env 를 갱신합니다(되돌리기 어려움):" -ForegroundColor Yellow
$instances | ForEach-Object { Write-Host ("  - {0}" -f $_.Name) }
if (-not $Force) {
    $answer = Read-Host "`n계속하시겠습니까? (y/N)"
    if ($answer -notmatch '^[Yy]$') {
        Write-Host '취소했습니다.' -ForegroundColor DarkGray
        return
    }
}

# ── .env 백업 ────────────────────────────────────────────────────────────────
$stamp     = Get-Date -Format 'yyyyMMdd_HHmmss'
$envBackup = "$EnvFile.bak.$stamp"
Copy-Item -LiteralPath $EnvFile -Destination $envBackup -Force
Write-Host ("`n  .env 백업: {0}" -f $envBackup) -ForegroundColor DarkGray

# T-SQL 문자열 리터럴용으로 작은따옴표를 이스케이프합니다('→'').
$newEsc = $newPw -replace "'", "''"
$oldEsc = $oldPw -replace "'", "''"

# ── 순방향: 각 인스턴스에 (이전 비밀번호로 접속) 새 비밀번호 적용 ──────────────
Write-Host "`n=== 적용 ===" -ForegroundColor Cyan
$changed     = New-Object System.Collections.Generic.List[object]
$forwardFail = $null
foreach ($inst in $instances) {
    $r = Invoke-Sql -Container $inst.Name -Password $oldPw `
                    -Query "ALTER LOGIN [sa] WITH PASSWORD = N'$newEsc';"
    if ($r.Success) {
        $changed.Add($inst)
        Write-Host ("  [OK]   {0}" -f $inst.Name) -ForegroundColor Green
    } else {
        $forwardFail = [pscustomobject]@{ Instance = $inst.Name; Error = $r.Output }
        Write-Host ("  [실패] {0}: {1}" -f $inst.Name, $r.Output) -ForegroundColor Red
        break   # 즉시 멈추고 롤백으로
    }
}

# ── 실패 시 롤백: 이미 바꾼 인스턴스를 (새 비밀번호로 접속) 이전 값으로 원복 ────
if ($forwardFail) {
    Write-Host "`n=== 롤백 (이미 바꾼 인스턴스를 원복) ===" -ForegroundColor Yellow
    $rollbackFail = @()
    foreach ($inst in $changed) {
        $r = Invoke-Sql -Container $inst.Name -Password $newPw `
                        -Query "ALTER LOGIN [sa] WITH PASSWORD = N'$oldEsc';"
        if ($r.Success) {
            Write-Host ("  [원복] {0}" -f $inst.Name) -ForegroundColor DarkGray
        } else {
            $rollbackFail += $inst.Name
            Write-Host ("  [원복실패] {0}: {1}" -f $inst.Name, $r.Output) -ForegroundColor Red
        }
    }

    if ($rollbackFail.Count -eq 0) {
        Write-Host "`n회전 실패 → 전 인스턴스를 기존 비밀번호로 원복했습니다. .env 는 변경하지 않았습니다." -ForegroundColor Yellow
        throw ("회전 실패({0}: {1}). 롤백 완료 — farm 은 기존 상태입니다." -f $forwardFail.Instance, $forwardFail.Error)
    } else {
        # 원복까지 실패 → 인스턴스별 비밀번호가 갈렸을 수 있음. 사람이 직접 맞춰야 함.
        Write-Host "`n[치명적] 롤백 실패 인스턴스: $($rollbackFail -join ', ')" -ForegroundColor Red
        Write-Host "  이 인스턴스들은 '새 비밀번호' 상태일 수 있습니다. 아래 값으로 직접 확인/정정하세요." -ForegroundColor Red
        Write-Host ("  새 비밀번호: {0}" -f $newPw) -ForegroundColor Yellow
        Write-Host ("  이전 .env 백업: {0}" -f $envBackup) -ForegroundColor DarkGray
        throw '회전과 롤백이 모두 실패했습니다. 수동 개입이 필요합니다(.env 는 변경하지 않음).'
    }
}

# ── 전부 성공 → .env 갱신 ─────────────────────────────────────────────────────
Set-DotEnvValue -Key 'MSSQL_SA_PASSWORD' -Value $newPw | Out-Null

Write-Host "`n=== 완료 ===" -ForegroundColor Cyan
Write-Host ("전 인스턴스({0}개) sa 비밀번호 회전 완료. .env 갱신됨." -f @($instances).Count) -ForegroundColor Green
if ($Generate) {
    Write-Host ("  새 비밀번호: {0}" -f $newPw) -ForegroundColor Yellow
    Write-Host '  (안전한 곳에 보관하세요. .env 에 평문으로 저장돼 있습니다.)' -ForegroundColor DarkGray
}
Write-Host ("  이전 .env 백업: {0}" -f $envBackup) -ForegroundColor DarkGray
Write-Host '  참고: 실행 중 컨테이너의 환경변수(MSSQL_SA_PASSWORD)는 그대로이나, 로그인 인증은 새 값으로 동작합니다.' -ForegroundColor DarkGray
