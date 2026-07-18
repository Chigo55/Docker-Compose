#Requires -Version 5.1
<#
.SYNOPSIS
    farm 전체 상태를 한 장의 HTML 리포트로 저장합니다. (읽기 전용)

.DESCRIPTION
    무인 운영에서 상태를 한눈에 보도록, 다음 3가지를 모아 HTML 파일로 만듭니다.
      1) 인스턴스 상태 : State / Health / TCP 응답 / 데이터 용량
      2) 최근 백업     : <BACKUP_ROOT>\<컨테이너>\ 의 가장 최근 백업 파일과 개수
      3) DB 인벤토리   : 실행 중 인스턴스의 sys.databases (상태·복구 모델·크기)

    아무것도 바꾸지 않는 조회 전용 스크립트입니다. 스케줄러로 주기 생성해 두면
    브라우저로 열어 farm 현황을 확인할 수 있습니다.

.EXAMPLE
    .\scripts\report.ps1
    기본 위치(<DATA_ROOT>\_report\farm_<시각>.html)에 리포트를 만듭니다.

.EXAMPLE
    .\scripts\report.ps1 -OutFile C:\docker\_report\farm.html -Open
    지정 경로에 만들고 브라우저로 엽니다.

.EXAMPLE
    .\scripts\report.ps1 -NoSize
    데이터 용량 계산을 생략해 더 빠르게 만듭니다.
#>
[CmdletBinding()]
param(
    [string]$OutFile,      # 저장 경로 (안 주면 <DATA_ROOT>\_report\farm_<시각>.html)
    [switch]$NoSize,       # 붙이면: 데이터 용량 계산 생략 (빠름)
    [switch]$Open          # 붙이면: 완료 후 기본 브라우저로 엶
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot

# Test-TcpPort(포트 응답)·Get-DirSizeMB(데이터 용량)는 _common.ps1 에 있습니다.
# (status.ps1 과 공유 — 예전엔 두 스크립트에 복제돼 있었습니다. 이슈 #14)


# ═══════════════════════════════════════════════════════════════════════════
#  여기서부터 메인 흐름
# ═══════════════════════════════════════════════════════════════════════════

Assert-Docker
$config = Read-DotEnv

$backupRoot = $config['BACKUP_ROOT']
$dataRoot   = $config['DATA_ROOT']
$project    = $config['COMPOSE_PROJECT_NAME']

# 저장 경로 결정 (안 주면 <DATA_ROOT>\_report\farm_<시각>.html)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
if (-not $OutFile) {
    $baseDir = if ($dataRoot) { Join-Path $dataRoot '_report' } else { Join-Path $RepoRoot '_report' }
    $OutFile = Join-Path $baseDir ("farm_{0}.html" -f $stamp)
}
$outDir = Split-Path -Parent $OutFile
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$instances = Get-Instances
Write-Host "`n=== 리포트 생성 ===" -ForegroundColor Cyan
Write-Host ("  대상: {0} 개 인스턴스" -f @($instances).Count)

# ── 1) 인스턴스 상태 ─────────────────────────────────────────────────────────
$statusRows = foreach ($inst in $instances) {
    $running = Test-ContainerRunning -Container $inst.Name
    $health  = Get-ContainerHealth -Container $inst.Name
    $state   = if ($running) { 'running' } elseif ($health -eq 'missing') { '(없음)' } else { 'stopped' }
    $tcp     = if ($running) { if (Test-TcpPort -Port $inst.Port) { 'OK' } else { '응답없음' } } else { '-' }
    $healthCol = if ($health -in @('none', 'missing')) { '-' } else { $health }
    $size    = if ($NoSize) { '-' } else {
                   $mb = Get-DirSizeMB -Path $inst.DataDir
                   if ($null -eq $mb) { 'N/A' } else { "$mb" }
               }
    [pscustomobject]@{
        Instance = $inst.Name; Service = $inst.Service; State = $state
        Health = $healthCol; Port = $inst.Port; TCP = $tcp; 'Data(MB)' = $size
    }
}

# ── 2) 최근 백업 ─────────────────────────────────────────────────────────────
$backupRows = foreach ($inst in $instances) {
    $hostDir = if ($backupRoot) { Join-Path $backupRoot $inst.Name } else { $null }
    $files   = if ($hostDir -and (Test-Path $hostDir)) {
                   @(Get-ChildItem -Path $hostDir -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Extension -in '.bak', '.dif', '.trn' })
               } else { @() }
    if ($files.Count -eq 0) {
        [pscustomobject]@{ Instance = $inst.Name; '최근 백업' = '(없음)'; '유형' = '-'; 'MB' = '-'; '시각' = '-'; '파일수' = 0 }
    } else {
        $latest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        [pscustomobject]@{
            Instance   = $inst.Name
            '최근 백업' = $latest.Name
            '유형'     = $latest.Extension.TrimStart('.')
            'MB'       = [math]::Round($latest.Length / 1MB, 1)
            '시각'     = $latest.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
            '파일수'   = $files.Count
        }
    }
}

# ── 3) DB 인벤토리 (실행 중 인스턴스만 조회) ─────────────────────────────────
$dbQuery = @"
SET NOCOUNT ON;
SELECT d.name, d.state_desc, d.recovery_model_desc,
       CAST(SUM(mf.size) * 8.0 / 1024 AS DECIMAL(18,1))
FROM sys.databases d
JOIN sys.master_files mf ON mf.database_id = d.database_id
GROUP BY d.name, d.state_desc, d.recovery_model_desc
ORDER BY d.name;
"@
$dbRows = foreach ($inst in $instances) {
    if (-not (Test-ContainerRunning -Container $inst.Name)) { continue }   # 꺼진 인스턴스는 조회 불가
    $res = Invoke-Sql -Container $inst.Name -Separator '|' -Query $dbQuery
    if (-not $res.Success) {
        [pscustomobject]@{ Instance = $inst.Name; DB = '(조회 실패)'; '상태' = '-'; '복구모델' = '-'; 'MB' = '-' }
        continue
    }
    foreach ($line in ($res.Output -split "`n")) {
        $c = $line -split '\|'
        if ($c.Count -lt 4) { continue }
        [pscustomobject]@{
            Instance = $inst.Name; DB = $c[0].Trim(); '상태' = $c[1].Trim()
            '복구모델' = $c[2].Trim(); 'MB' = $c[3].Trim()
        }
    }
}

# ── HTML 조립 ────────────────────────────────────────────────────────────────
$style = @"
<style>
 body { font-family: 'Segoe UI','Malgun Gothic',sans-serif; margin: 24px; color: #222; }
 h1 { font-size: 20px; margin-bottom: 2px; }
 h2 { font-size: 15px; margin-top: 26px; border-bottom: 1px solid #ccc; padding-bottom: 4px; }
 table { border-collapse: collapse; margin-top: 8px; }
 th, td { border: 1px solid #ccc; padding: 4px 10px; font-size: 13px; text-align: left; }
 th { background: #f2f2f2; }
 .meta { color: #666; font-size: 12px; }
</style>
"@

$now         = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$statusHtml  = @($statusRows) | ConvertTo-Html -Fragment
$backupHtml  = @($backupRows) | ConvertTo-Html -Fragment
$dbHtml      = if (@($dbRows).Count -gt 0) { @($dbRows) | ConvertTo-Html -Fragment } else { '<p class="meta">실행 중인 인스턴스가 없어 DB 인벤토리를 조회하지 못했습니다.</p>' }

$html = @"
<!DOCTYPE html>
<html lang="ko"><head><meta charset="utf-8"><title>MSSQL Farm 리포트</title>$style</head>
<body>
<h1>MSSQL Farm 리포트</h1>
<p class="meta">프로젝트: $project · 생성: $now</p>
<h2>1. 인스턴스 상태</h2>
$statusHtml
<h2>2. 최근 백업</h2>
$backupHtml
<h2>3. DB 인벤토리 (실행 중 인스턴스)</h2>
$dbHtml
</body></html>
"@

# HTML 은 <meta charset="utf-8"> 를 두었으므로 UTF-8 로 저장합니다.
[System.IO.File]::WriteAllText($OutFile, $html, (New-Object System.Text.UTF8Encoding($false)))

Write-Host ("`n리포트 저장: {0}" -f $OutFile) -ForegroundColor Green
if ($Open) { Invoke-Item -LiteralPath $OutFile }
