#Requires -Version 5.1
<#
.SYNOPSIS
    한 인스턴스의 DB 를 다른 인스턴스로 복제합니다. (backup.ps1 + restore.ps1 조합)

.DESCRIPTION
    "운영 DB 를 스테이징으로 복사" 같은 작업을 한 번의 명령으로 처리합니다.
    새 로직을 만들지 않고 기존 스크립트를 그대로 조합합니다:

      1) From 인스턴스에서 DB 를 copy-only 전체 백업 (backup.ps1 -CopyOnly)
         · copy-only 라서 From 의 백업 체인(차등 기준 등)에 영향을 주지 않습니다.
      2) 방금 만든 .bak 을 To 인스턴스에 복원 (restore.ps1 -BackupFile [-AsDatabase])

    -AsDatabase 로 다른 이름으로 복제할 수 있습니다. 이름이 다르면 같은 인스턴스 안에서
    클론(예: MyDb → MyDb_clone)도 가능합니다.

    ※ To 인스턴스의 대상 DB 를 덮어쓰는 파괴적 작업입니다. -Force 가 없으면 먼저 확인합니다.
    전송에 쓴 백업 파일은 <BACKUP_ROOT>\<From 컨테이너>\ 에 그대로 남습니다(보관 정책이 정리).

.EXAMPLE
    .\scripts\copy-db.ps1 -From db2022a -To db2022b -Database MyDb
    db2022a 의 MyDb 를 db2022b 에 같은 이름으로 복제합니다.

.EXAMPLE
    .\scripts\copy-db.ps1 -From db2022a -To db2022b -Database MyDb -AsDatabase MyDb_staging
    db2022a 의 MyDb 를 db2022b 에 MyDb_staging 이라는 다른 이름으로 복제합니다.

.EXAMPLE
    .\scripts\copy-db.ps1 -From db2022a -To db2022a -Database MyDb -AsDatabase MyDb_clone
    같은 인스턴스 안에서 다른 이름으로 클론합니다.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$From,   # 원본 인스턴스 서비스키 (예: db2022a)
    [Parameter(Mandatory)][string]$To,     # 대상 인스턴스 서비스키 (예: db2022b)
    [string]$Database,                     # 복제할 DB 이름 (안 주면 .env 의 BACKUP_DATABASE 사용)
    [string]$AsDatabase,                   # 대상에서 쓸 다른 이름 (안 주면 원본과 같은 이름)
    [switch]$Force                         # 붙이면: 덮어쓰기 확인 프롬프트를 건너뜀
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot

Assert-Docker
$config = Read-DotEnv

# ── 설정 해석 ────────────────────────────────────────────────────────────────
if (-not $Database) { $Database = $config['BACKUP_DATABASE'] }
if (-not $Database) {
    throw "DB 이름이 없습니다. -Database 를 지정하거나 .env 의 BACKUP_DATABASE 를 채우세요."
}
$backupRoot = $config['BACKUP_ROOT']
if (-not $backupRoot) {
    throw '.env 에 BACKUP_ROOT 가 없습니다.'
}

# From/To 서비스키를 검증(오타 방지)하고 소문자로 정규화한 뒤 인스턴스 객체를 얻습니다.
$fromKey  = (Resolve-Services -Service @($From))[0]
$toKey    = (Resolve-Services -Service @($To))[0]
$fromInst = Get-Instances | Where-Object { $_.Service -eq $fromKey }
$toInst   = Get-Instances | Where-Object { $_.Service -eq $toKey }

# 대상 DB 이름 (다른 이름 복제 시 -AsDatabase, 아니면 원본과 동일)
$targetDb = if ($AsDatabase) { $AsDatabase } else { $Database }

# 같은 인스턴스에 같은 이름으로 복제하면 원본을 자기 자신으로 덮어써 무의미/위험합니다.
if ($fromKey -eq $toKey -and $targetDb -eq $Database) {
    throw "같은 인스턴스($fromKey)에 같은 이름($Database)으로는 복제할 수 없습니다. -AsDatabase 로 다른 이름을 지정하세요."
}

Write-Host "`n=== DB 복제 ===" -ForegroundColor Cyan
Write-Host ("  원본: {0} ({1}) 의 [{2}]" -f $fromKey, $fromInst.Name, $Database)
Write-Host ("  대상: {0} ({1}) 의 [{2}]" -f $toKey, $toInst.Name, $targetDb)

# ── 파괴적 작업(대상 DB 덮어쓰기) 확인 ───────────────────────────────────────
Write-Host ("`n{0} 의 [{1}] 를 덮어씁니다 (있다면 기존 데이터는 사라집니다)." -f $toInst.Name, $targetDb) -ForegroundColor Yellow
if (-not $Force) {
    $answer = Read-Host "`n계속하시겠습니까? (y/N)"
    if ($answer -notmatch '^[Yy]$') {
        Write-Host '취소했습니다.' -ForegroundColor DarkGray
        return
    }
}

# ── 1) 원본에서 copy-only 전체 백업 ──────────────────────────────────────────
# 자식 스크립트로 실행합니다. 실패하면 backup.ps1 이 exit 1 을 내므로 $LASTEXITCODE 로 감지합니다.
Write-Host "`n[1/2] 원본 백업 (copy-only)" -ForegroundColor Cyan
& "$PSScriptRoot\backup.ps1" -Service $fromKey -Database $Database -CopyOnly
if ($LASTEXITCODE -ne 0) { throw ("원본 백업 실패 ({0} / {1})." -f $fromKey, $Database) }

# 방금 만든 백업 파일(원본 컨테이너 폴더의 최신 <DB>_*.bak)을 찾습니다.
$fromDir = Join-Path $backupRoot $fromInst.Name
$bak = Get-ChildItem -Path $fromDir -Filter ("{0}_*.bak" -f $Database) -File -ErrorAction SilentlyContinue |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $bak) { throw ("백업 파일을 찾지 못했습니다: {0}\{1}_*.bak" -f $fromDir, $Database) }
Write-Host ("  백업 파일: {0}" -f $bak.FullName) -ForegroundColor DarkGray

# ── 2) 대상에 복원 (다른 이름이면 -AsDatabase). 이미 확인했으니 restore 는 -Force. ──
Write-Host "`n[2/2] 대상 복원" -ForegroundColor Cyan
& "$PSScriptRoot\restore.ps1" -Service $toKey -Database $Database -AsDatabase $AsDatabase -BackupFile $bak.FullName -Force
if ($LASTEXITCODE -ne 0) { throw ("대상 복원 실패 ({0} / {1})." -f $toKey, $targetDb) }

Write-Host ("`n복제 완료: {0}[{1}] → {2}[{3}]" -f $fromInst.Name, $Database, $toInst.Name, $targetDb) -ForegroundColor Green
Write-Host ("  전송에 쓴 백업은 보존됩니다: {0}" -f $bak.FullName) -ForegroundColor DarkGray
