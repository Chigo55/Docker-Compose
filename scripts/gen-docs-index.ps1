#Requires -Version 5.1
<#
.SYNOPSIS
    ADR·rules 인덱스 표를 각 파일의 frontmatter 에서 생성한다.

.DESCRIPTION
    이 저장소는 인덱스 표(`.claude/adr/README.md`·`.claude/rules/README.md` 의 "목록")를
    저장소에 커밋하지 않는다. 여러 PR 이 같은 표의 마지막 줄에 동시에 행을 append 하다
    결정적으로 머지 충돌을 내던 문제를 없애기 위해서다([ADR-0021]).

    대신 각 항목의 한 줄 요약은 그 파일 상단 frontmatter(`summary:`)에 두고, 이 스크립트가
    필요할 때 표를 만들어 낸다.

      · (기본)      ADR·rules 인덱스 표를 표준출력으로 낸다.
      · -Out <dir>  생성한 표를 <dir> 아래 파일로 쓴다(gitignored, 온디맨드 뷰).
      · -Check      모든 대상 .md 에 summary frontmatter 가 있는지 검증한다.
                    빠진 게 있으면 목록을 내고 종료 코드 1 을 돌려준다(check.ps1/CI 용).

    frontmatter 는 표준 YAML(`--- ... ---`) 형식이라 GitHub 이 파일을 열 때 표로 렌더링해,
    표를 커밋하지 않아도 요약이 파일 안에서 보인다.

.EXAMPLE
    .\scripts\gen-docs-index.ps1
    ADR·rules 인덱스 표를 화면에 출력합니다.

.EXAMPLE
    .\scripts\gen-docs-index.ps1 -Check
    모든 ADR·rules 파일에 summary frontmatter 가 있는지 검증합니다(없으면 exit 1).

.EXAMPLE
    .\scripts\gen-docs-index.ps1 -Out docs\_generated
    인덱스 표를 docs\_generated 아래 파일로 씁니다(gitignore 대상).
#>
[CmdletBinding()]
param(
    [string]$Out,     # 주면: 생성 결과를 이 폴더 아래 파일로 쓴다(gitignored)
    [switch]$Check    # 주면: 표를 내지 않고 frontmatter 완비 여부만 검증한다
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"   # $RepoRoot 확보(자동 발견/헬퍼 재사용)


# ═══════════════════════════════════════════════════════════════════════════
#  순수 파서 (단위 테스트 대상) — 파일이 아니라 텍스트를 받는다.
# ═══════════════════════════════════════════════════════════════════════════

# ---------------------------------------------------------------------------
#  ConvertFrom-DocFrontmatter : 맨 위 '--- ... ---' 블록을 key→value 로 파싱.
#  frontmatter 가 없으면 빈 해시테이블을 돌려준다. 값의 감싼 따옴표는 벗긴다.
# ---------------------------------------------------------------------------
function ConvertFrom-DocFrontmatter {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $map   = @{}
    $lines = $Text -split "`r?`n"
    if ($lines.Count -lt 1 -or $lines[0].Trim() -ne '---') { return $map }

    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { break }   # 닫는 구분선에서 종료
        if ($lines[$i] -match '^\s*([A-Za-z0-9_-]+)\s*:\s*(.*)$') {
            $key = $matches[1]
            $val = $matches[2].Trim()
            if ($val.Length -ge 2) {
                $q = $val[0]
                if (($q -eq '"' -or $q -eq "'") -and $val[$val.Length - 1] -eq $q) {
                    $val = $val.Substring(1, $val.Length - 2)
                }
            }
            $map[$key] = $val
        }
    }
    return $map
}

# ---------------------------------------------------------------------------
#  Get-DocH1 : 텍스트에서 첫 번째 '# 제목' 줄의 제목을 돌려준다(없으면 $null).
# ---------------------------------------------------------------------------
function Get-DocH1 {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^#\s+(.+?)\s*$') { return $matches[1] }
    }
    return $null
}

# ---------------------------------------------------------------------------
#  Get-AdrTitle : ADR H1 에서 'ADR-NNNN: ' 접두사를 벗겨 제목만 돌려준다.
# ---------------------------------------------------------------------------
function Get-AdrTitle {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$H1)
    return ($H1 -replace '^ADR-\d+:\s*', '')
}


# ═══════════════════════════════════════════════════════════════════════════
#  파일 스캔 → 항목 목록
# ═══════════════════════════════════════════════════════════════════════════

# ---------------------------------------------------------------------------
#  Get-IndexDocs : 폴더에서 README 를 뺀 .md 를 이름순으로 돌려준다.
# ---------------------------------------------------------------------------
function Get-IndexDocs {
    param([Parameter(Mandatory)][string]$Dir)

    if (-not (Test-Path $Dir)) { return @() }
    return Get-ChildItem -Path $Dir -Filter '*.md' -File |
           Where-Object { $_.Name -ne 'README.md' } |
           Sort-Object Name
}

# ---------------------------------------------------------------------------
#  Get-AdrEntries : .claude/adr/*.md → {Slug, Num, Title, Summary, HasSummary}
# ---------------------------------------------------------------------------
function Get-AdrEntries {
    $dir = Join-Path $RepoRoot '.claude\adr'
    foreach ($f in (Get-IndexDocs -Dir $dir)) {
        $text    = Get-Content -Path $f.FullName -Raw -Encoding UTF8
        $fm      = ConvertFrom-DocFrontmatter -Text $text
        $h1      = Get-DocH1 -Text $text
        $num     = if ($f.Name -match '^(\d+)') { $matches[1] } else { '' }
        $title   = if ($h1) { Get-AdrTitle -H1 $h1 } else { '' }
        $summary = [string]$fm['summary']
        [pscustomobject]@{
            Slug       = $f.Name
            Num        = $num
            Title      = $title
            Summary    = $summary
            HasSummary = -not [string]::IsNullOrWhiteSpace($summary)
        }
    }
}

# ---------------------------------------------------------------------------
#  Get-RulesEntries : .claude/rules/*.md → {Slug, Summary, HasSummary}
# ---------------------------------------------------------------------------
function Get-RulesEntries {
    $dir = Join-Path $RepoRoot '.claude\rules'
    foreach ($f in (Get-IndexDocs -Dir $dir)) {
        $text    = Get-Content -Path $f.FullName -Raw -Encoding UTF8
        $fm      = ConvertFrom-DocFrontmatter -Text $text
        $summary = [string]$fm['summary']
        [pscustomobject]@{
            Slug       = $f.Name
            Summary    = $summary
            HasSummary = -not [string]::IsNullOrWhiteSpace($summary)
        }
    }
}


# ═══════════════════════════════════════════════════════════════════════════
#  표 렌더링
# ═══════════════════════════════════════════════════════════════════════════

function Format-AdrIndex {
    $lines = @('| # | 제목 | 요약 |', '|---|------|------|')
    foreach ($e in (Get-AdrEntries)) {
        $lines += '| [{0}]({1}) | {2} | {3} |' -f $e.Num, $e.Slug, $e.Title, $e.Summary
    }
    return ($lines -join "`n")
}

function Format-RulesIndex {
    $lines = @('| 파일 | 다루는 것 |', '|------|-----------|')
    foreach ($e in (Get-RulesEntries)) {
        $lines += '| [{0}]({0}) | {1} |' -f $e.Slug, $e.Summary
    }
    return ($lines -join "`n")
}


# ═══════════════════════════════════════════════════════════════════════════
#  검증 (-Check)
# ═══════════════════════════════════════════════════════════════════════════

# summary frontmatter 가 빠진 파일 목록을 돌려준다(경로 상대화).
function Get-MissingSummary {
    $bad = @()
    foreach ($e in (Get-AdrEntries))   { if (-not $e.HasSummary) { $bad += ".claude\adr\$($e.Slug)" } }
    foreach ($e in (Get-RulesEntries)) { if (-not $e.HasSummary) { $bad += ".claude\rules\$($e.Slug)" } }
    return $bad
}


# ═══════════════════════════════════════════════════════════════════════════
#  Invoke-Main : 스크립트를 직접 실행했을 때만 돈다(테스트가 dot-source 하면 건너뜀).
# ═══════════════════════════════════════════════════════════════════════════
function Invoke-Main {
    if ($Check) {
        Write-Host "=== 문서 인덱스 검증 (frontmatter summary) ===" -ForegroundColor Cyan
        $missing = @(Get-MissingSummary)
        if ($missing.Count -gt 0) {
            Write-Host ("  summary frontmatter 가 없는 파일 {0}건:" -f $missing.Count) -ForegroundColor Red
            foreach ($m in $missing) { Write-Host ("    - {0}" -f $m) -ForegroundColor Red }
            Write-Host "  각 파일 맨 위에 다음을 추가하세요:" -ForegroundColor DarkGray
            Write-Host "    ---"                              -ForegroundColor DarkGray
            Write-Host '    summary: "한 줄 요약"'            -ForegroundColor DarkGray
            Write-Host "    ---"                              -ForegroundColor DarkGray
            exit 1
        }
        Write-Host "  전체 항목에 summary 가 있습니다." -ForegroundColor Green
        exit 0
    }

    $adr   = Format-AdrIndex
    $rules = Format-RulesIndex

    if ($Out) {
        $dir = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $RepoRoot $Out }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $adrPath   = Join-Path $dir 'adr-index.md'
        $rulesPath = Join-Path $dir 'rules-index.md'
        Set-Content -Path $adrPath   -Value $adr   -Encoding UTF8
        Set-Content -Path $rulesPath -Value $rules -Encoding UTF8
        Write-Host ("생성: {0}" -f $adrPath)   -ForegroundColor Green
        Write-Host ("생성: {0}" -f $rulesPath) -ForegroundColor Green
    }
    else {
        Write-Host "## ADR 목록" -ForegroundColor Cyan
        Write-Output $adr
        Write-Output ""
        Write-Host "## rules 목록" -ForegroundColor Cyan
        Write-Output $rules
    }
}


# dot-source(테스트) 로 불릴 때는 InvocationName 이 '.' 이라 main 을 돌지 않는다.
if ($MyInvocation.InvocationName -ne '.') { Invoke-Main }
