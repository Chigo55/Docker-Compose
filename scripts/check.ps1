#Requires -Version 5.1
<#
.SYNOPSIS
    내부 개발 루프의 "검증 러너". 스크립트/설정을 고칠 때마다 빠르게 점검합니다.

.DESCRIPTION
    한 번에 세 단계를 돌립니다.
      1) 린트 (PSScriptAnalyzer) — scripts\ 와 tests\ 의 모든 .ps1 정적 분석.
         이 저장소의 의도된 관례와 충돌하는 규칙은 제외합니다:
           · PSAvoidUsingWriteHost   : 컬러 단계 출력은 이 저장소의 출력 방식(관례)
           · PSUseSingularNouns      : Get-Instances 등 컬렉션 반환 함수의 복수형은 의도
           · PSReviewUnusedParameter : 중첩 함수/스크립트블록에서 쓰는 파라미터를 오탐
           · PSAvoidUsingPlainTextForPassword          : SA 비밀번호를 평문으로 다루는 설계(ADR-0013)
           · PSUseShouldProcessForStateChangingFunctions: ShouldProcess 대신 수동 y/N 프롬프트 관례(CONVENTIONS §9)
      2) 규약 점검 (doctor.ps1) — .env/compose 규약 + docker compose config 렌더링.
         (doctor 가 마지막 단계에서 compose 렌더링까지 하므로 여기서 따로 하지 않습니다.)
      3) 문서 인덱스 검증 (gen-docs-index.ps1 -Check) — ADR·rules·scripts 인덱스 표를 커밋하지
         않는 대신(ADR-0021·ADR-0022), 각 파일에 summary frontmatter 가 있는지, 그리고
         scripts\*.ps1 마다 docs\scripts\<name>.md 사용법 문서가 있는지 확인합니다.

    -Test 를 주면 끝에 Pester 단위 테스트(test.ps1)까지 이어서 돌립니다.
    -Watch 를 주면 scripts\ / compose\ / tests\ 변경을 감시해 자동으로 재실행합니다.

    오류가 하나라도 있으면 종료 코드 1 을 돌려줍니다(자동화/CI 감지용). -Watch 중에는
    종료하지 않고 계속 감시합니다.

.EXAMPLE
    .\scripts\check.ps1
    린트 + 규약 점검을 한 번 실행합니다.

.EXAMPLE
    .\scripts\check.ps1 -Test
    린트 + 규약 점검 + 단위 테스트까지 실행합니다.

.EXAMPLE
    .\scripts\check.ps1 -Watch -Test
    파일이 바뀔 때마다 전체 루프를 자동으로 다시 돌립니다.

.EXAMPLE
    .\scripts\check.ps1 -Install
    없는 개발 모듈(PSScriptAnalyzer)을 CurrentUser 로 설치한 뒤 실행합니다.
#>
[CmdletBinding()]
param(
    [switch]$Watch,        # 붙이면: 소스 변경을 감시해 자동 재실행
    [switch]$Test,         # 붙이면: 끝에 Pester 단위 테스트(test.ps1)도 실행
    [switch]$Install,      # 붙이면: 없는 개발 모듈을 CurrentUser 로 설치
    [int]$Interval = 2     # -Watch 폴링 간격(초)
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
. "$PSScriptRoot\lib\_devtools.ps1"
Set-Location -Path $RepoRoot


# 이 저장소 관례와 충돌해 제외하는 규칙들 (.DESCRIPTION 에 이유 명시).
$script:ExcludedRules = @(
    'PSAvoidUsingWriteHost', 'PSUseSingularNouns', 'PSReviewUnusedParameter',
    'PSAvoidUsingPlainTextForPassword', 'PSUseShouldProcessForStateChangingFunctions'
)


# ═══════════════════════════════════════════════════════════════════════════
#  Invoke-Lint : PSScriptAnalyzer 로 .ps1 을 정적 분석합니다.
#  돌려주는 값: 'pass' | 'warn' | 'fail' | 'skip'
# ═══════════════════════════════════════════════════════════════════════════
function Invoke-Lint {
    Write-Host "`n=== 린트 (PSScriptAnalyzer) ===" -ForegroundColor Cyan

    if (-not (Assert-DevModule -Name PSScriptAnalyzer -MinimumVersion '1.0' -Install:$Install)) {
        return 'skip'
    }
    Import-Module PSScriptAnalyzer -MinimumVersion '1.0'

    $roots = @('scripts', 'tests') | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path $_ }
    $files = Get-ChildItem -Path $roots -Recurse -Filter '*.ps1' -File

    $nErr = 0
    $nWarn = 0
    foreach ($f in $files) {
        $rel    = $f.FullName.Substring($RepoRoot.Length + 1)
        $issues = Invoke-ScriptAnalyzer -Path $f.FullName -Severity @('Error', 'Warning') `
                                        -ExcludeRule $script:ExcludedRules

        if (-not $issues) {
            Write-Host ("  [OK]   {0}" -f $rel) -ForegroundColor Green
            continue
        }

        foreach ($i in $issues) {
            if ($i.Severity -eq 'Error') { $nErr++ } else { $nWarn++ }
            $color = if ($i.Severity -eq 'Error') { 'Red' } else { 'Yellow' }
            $tag   = if ($i.Severity -eq 'Error') { '[오류]' } else { '[경고]' }
            Write-Host ("  {0} {1}:{2}  {3}  {4}" -f $tag, $rel, $i.Line, $i.RuleName, $i.Message) -ForegroundColor $color
        }
    }

    if ($nErr -gt 0)  { return 'fail' }
    if ($nWarn -gt 0) { return 'warn' }
    Write-Host ("  전체 {0}개 파일 통과" -f @($files).Count) -ForegroundColor DarkGray
    return 'pass'
}


# ═══════════════════════════════════════════════════════════════════════════
#  Invoke-Doctor : doctor.ps1 을 실행하고 종료 코드를 돌려줍니다.
#
#  같은 프로세스에서 '& doctor.ps1' 로 호출합니다. doctor 는 실패 시 'exit 1' 을
#  하지만, 호출 연산자(&)로 부른 스크립트의 exit 는 부모를 죽이지 않고 $LASTEXITCODE
#  만 남기고 돌아옵니다. (검증 완료) 자식 프로세스로 띄우면 컬러 출력이 유실됩니다.
# ═══════════════════════════════════════════════════════════════════════════
function Invoke-Doctor {
    Write-Host "`n=== 규약 점검 + compose 렌더링 (doctor) ===" -ForegroundColor Cyan
    $doctor = Join-Path $PSScriptRoot 'doctor.ps1'
    & $doctor
    return $LASTEXITCODE
}


# ═══════════════════════════════════════════════════════════════════════════
#  Invoke-DocsIndex : gen-docs-index.ps1 -Check 로 문서 인덱스 frontmatter 를 검증합니다.
#
#  모델 A(ADR-0021·ADR-0022): ADR·rules·scripts 인덱스 표를 저장소에 커밋하지 않는 대신,
#  각 파일에 summary frontmatter 가 있는지(없으면 인덱스 생성이 깨지므로)와, 스크립트마다
#  docs\scripts\<name>.md 사용법 문서가 있는지를 여기서 확인합니다.
#  Invoke-Doctor 와 같은 방식 — & 로 호출해 자식의 exit 를 $LASTEXITCODE 로만 받습니다.
# ═══════════════════════════════════════════════════════════════════════════
function Invoke-DocsIndex {
    $gen = Join-Path $PSScriptRoot 'gen-docs-index.ps1'
    & $gen -Check
    return $LASTEXITCODE
}


# ═══════════════════════════════════════════════════════════════════════════
#  Invoke-Tests : test.ps1 을 실행하고 종료 코드를 돌려줍니다. (Invoke-Doctor 와 동일 방식)
# ═══════════════════════════════════════════════════════════════════════════
function Invoke-Tests {
    $test = Join-Path $PSScriptRoot 'test.ps1'
    & $test -Install:$Install
    return $LASTEXITCODE
}


# ═══════════════════════════════════════════════════════════════════════════
#  Invoke-AllChecks : 한 사이클(린트 → doctor → (선택)테스트)을 돌리고 요약합니다.
#  돌려주는 값: 전부 통과면 $true, 아니면 $false.
# ═══════════════════════════════════════════════════════════════════════════
function Invoke-AllChecks {
    $lint       = Invoke-Lint
    $doctorCode = Invoke-Doctor
    $docsCode   = Invoke-DocsIndex
    $testCode   = 0
    if ($Test) { $testCode = Invoke-Tests }

    Write-Host "`n=== 요약 ===" -ForegroundColor Cyan

    $lintText, $lintColor = switch ($lint) {
        'pass' { '통과',   'Green' }
        'warn' { '경고',   'Yellow' }
        'fail' { '오류',   'Red' }
        'skip' { '건너뜀', 'DarkGray' }
    }
    Write-Host ("  린트   : {0}" -f $lintText) -ForegroundColor $lintColor
    Write-Host ("  doctor : {0}" -f $(if ($doctorCode -eq 0) { '통과' } else { '오류' })) `
        -ForegroundColor $(if ($doctorCode -eq 0) { 'Green' } else { 'Red' })
    Write-Host ("  인덱스 : {0}" -f $(if ($docsCode -eq 0) { '통과' } else { '오류' })) `
        -ForegroundColor $(if ($docsCode -eq 0) { 'Green' } else { 'Red' })
    if ($Test) {
        Write-Host ("  테스트 : {0}" -f $(if ($testCode -eq 0) { '통과' } else { '실패' })) `
            -ForegroundColor $(if ($testCode -eq 0) { 'Green' } else { 'Red' })
    }

    # 린트 경고(warn)/건너뜀(skip)은 기동을 막지 않습니다. 오류(fail)와 doctor/인덱스/테스트 실패만 실패로 봅니다.
    $ok = ($lint -ne 'fail') -and ($doctorCode -eq 0) -and ($docsCode -eq 0) -and ($testCode -eq 0)
    Write-Host ("`n{0}" -f $(if ($ok) { '전체 통과.' } else { '문제가 있습니다. 위 로그를 확인하세요.' })) `
        -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    return $ok
}


# ═══════════════════════════════════════════════════════════════════════════
#  실행
# ═══════════════════════════════════════════════════════════════════════════
if ($Watch) {
    $watchPaths = @('scripts', 'compose', 'tests', '.claude') |
                  ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path $_ }
    $last = $null
    Write-Host "감시 시작. 파일을 저장하면 자동으로 다시 검사합니다. (Ctrl+C 로 종료)" -ForegroundColor DarkGray
    while ($true) {
        $stamp = Get-WatchStamp -Path $watchPaths
        if ($stamp -ne $last) {
            Clear-Host
            Write-Host ("검사 실행 — {0}" -f (Get-Date -Format 'HH:mm:ss')) -ForegroundColor DarkGray
            [void] (Invoke-AllChecks)
            $last = $stamp
            Write-Host "`n파일 변경 감시 중... (Ctrl+C 로 종료)" -ForegroundColor DarkGray
        }
        Start-Sleep -Seconds $Interval
    }
} else {
    $ok = Invoke-AllChecks
    if (-not $ok) { exit 1 }   # 자동화/CI 가 실패를 감지할 수 있도록
}
