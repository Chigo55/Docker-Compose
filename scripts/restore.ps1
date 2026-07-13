#Requires -Version 5.1
<#
.SYNOPSIS
    백업(.bak)을 인스턴스에 복원(RESTORE)합니다. backup.ps1 의 짝입니다.

.DESCRIPTION
    "안전한 복원"을 위해 파일을 직접 붙이지 않고 SQL Server 엔진에게
    RESTORE DATABASE 를 시킵니다. 사람이 신경 쓰기 번거로운 부분을 자동화합니다.

      · 백업 파일 자동 선택 : <BACKUP_ROOT>\<컨테이너명>\<DB>_*.bak 중 가장 최신 파일
      · 논리 파일 자동 이동 : RESTORE FILELISTONLY 로 백업 안의 논리 파일명을 읽어
                              WITH MOVE 절을 자동으로 만들어 /var/opt/mssql/data 로 배치
      · 버전 자동 판별      : 2019/2022 sqlcmd 경로를 컨테이너에서 실제 확인(_common.ps1)
      · 활성 연결 정리      : 기존 DB 가 있으면 SINGLE_USER 로 연결을 끊고 덮어씁니다.

    한 인스턴스에 대한 처리 순서:
      1) 컨테이너 실행 확인
      2) 복원할 .bak 결정 (지정 없으면 해당 컨테이너 폴더의 최신 파일)
      3) docker cp 로 컨테이너 임시 폴더에 복사
      4) RESTORE FILELISTONLY 로 논리 파일명/유형(D/L) 파악 → WITH MOVE 구성
      5) (기존 DB 존재 시) SINGLE_USER 로 전환 후 RESTORE ... WITH REPLACE
      6) 컨테이너 안 임시 파일 삭제

    ※ 복원은 대상 DB 를 덮어쓰는 파괴적 작업입니다. -Force 가 없으면 먼저 확인합니다.
    한 인스턴스가 실패해도 나머지는 계속 진행하고, 마지막에 요약 표를 냅니다.
    실패가 하나라도 있으면 종료 코드 1 을 돌려줍니다(스케줄러 감지용).

.EXAMPLE
    .\scripts\restore.ps1 -Service db2019c -Database MyDb
    db2019c 의 최신 MyDb 백업을 복원합니다.

.EXAMPLE
    .\scripts\restore.ps1 -Database MyDb
    모든 인스턴스에서 각자의 최신 MyDb 백업을 복원합니다. (확인 프롬프트)

.EXAMPLE
    .\scripts\restore.ps1 -Service db2022b -BackupFile "C:\docker\_backup\Db2022B\MyDb_20260101_020000.bak"
    특정 .bak 파일을 db2022b 에 복원합니다. (-BackupFile 은 단일 -Service 와 함께 씁니다)

.EXAMPLE
    .\scripts\restore.ps1 -Service db2019c -Database MyDb -NoRecovery
    이후 로그 백업을 이어 복원할 수 있도록 RESTORING 상태로 둡니다.
#>
[CmdletBinding()]
param(
    [string]$Database,             # 복원할 DB 이름 (안 주면 .env 의 BACKUP_DATABASE 사용)
    [string[]]$Service = @(),      # 비우면 전체, 지정하면 그 인스턴스만
    [string]$BackupRoot,           # 백업 저장 최상위 폴더 (안 주면 .env 의 BACKUP_ROOT 사용)
    [string]$BackupFile,           # 특정 .bak 경로 직접 지정 (단일 -Service 와 함께)
    [string]$StagingDir,           # 컨테이너 안 임시 경로 (안 주면 .env 의 BACKUP_STAGING_DIR)
    [switch]$NoRecovery,           # 붙이면: WITH NORECOVERY (추가 로그 복원 대기)
    [switch]$Force                 # 붙이면: 덮어쓰기 확인 프롬프트 없이 진행
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot


# ═══════════════════════════════════════════════════════════════════════════
#  Resolve-BackupFile : 이 인스턴스에 복원할 .bak 호스트 경로를 결정합니다.
#  · -BackupFile 을 줬으면 그 파일을 검증해 그대로 사용
#  · 없으면 <BackupRoot>\<컨테이너명>\<DB>_*.bak 중 가장 최근 파일을 고릅니다.
# ═══════════════════════════════════════════════════════════════════════════
function Resolve-BackupFile {
    param(
        [Parameter(Mandatory)][pscustomobject]$Instance,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string]$BackupFile
    )

    if ($BackupFile) {
        if (-not (Test-Path $BackupFile)) { throw ("지정한 백업 파일이 없습니다: {0}" -f $BackupFile) }
        return (Get-Item -LiteralPath $BackupFile)
    }

    $hostDir = Join-Path $BackupRoot $Instance.Name
    if (-not (Test-Path $hostDir)) { throw ("백업 폴더가 없습니다: {0}" -f $hostDir) }

    # <DB>_로 시작하는 .bak 중 가장 최근 파일 하나
    $latest = Get-ChildItem -Path $hostDir -Filter ("{0}_*.bak" -f $Database) -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1

    if (-not $latest) { throw ("복원할 백업이 없습니다: {0}\{1}_*.bak" -f $hostDir, $Database) }
    return $latest
}


# ═══════════════════════════════════════════════════════════════════════════
#  Get-MoveClauses : 백업 안의 논리 파일명을 읽어 WITH MOVE 절을 만듭니다.
#  RESTORE FILELISTONLY 결과에서 LogicalName(1번째)·Type(3번째) 컬럼을 사용합니다.
#    Type 'D' = 데이터, 'L' = 로그. 그 외(F/S 등)는 자동 처리하지 않고 중단합니다.
#  대상 경로는 컨테이너의 데이터 폴더(/var/opt/mssql/data)로 통일합니다.
# ═══════════════════════════════════════════════════════════════════════════
function Get-MoveClauses {
    param(
        [Parameter(Mandatory)][string]$Container,
        [Parameter(Mandatory)][string]$RemoteBak,
        [Parameter(Mandatory)][string]$Database
    )

    # 컬럼을 '|' 로 구분해 받아 여러 컬럼을 안전하게 파싱합니다.
    $list = Invoke-Sql -Container $Container -Separator '|' -Query @"
SET NOCOUNT ON;
RESTORE FILELISTONLY FROM DISK = N'$RemoteBak';
"@
    if (-not $list.Success) { throw ("FILELISTONLY 실패: {0}" -f $list.Output) }

    $dataRoot = '/var/opt/mssql/data'
    $moves    = @()
    $dataN    = 0   # 데이터 파일 개수 (첫 개는 .mdf, 이후 .ndf)
    $logN     = 0   # 로그 파일 개수

    foreach ($line in ($list.Output -split "`n")) {
        if ($line -notmatch '\|') { continue }              # 데이터 줄이 아니면 건너뜀
        $cols = $line -split '\|'
        if ($cols.Count -lt 3) { continue }

        $logical = $cols[0].Trim()
        $type    = $cols[2].Trim().ToUpper()
        if (-not $logical) { continue }

        switch ($type) {
            'D' {
                $dataN++
                $fileName = if ($dataN -eq 1) { "$Database.mdf" } else { "${Database}_$dataN.ndf" }
            }
            'L' {
                $logN++
                $fileName = if ($logN -eq 1) { "${Database}_log.ldf" } else { "${Database}_log_$logN.ldf" }
            }
            default {
                throw ("자동 복원이 지원하지 않는 파일 유형($type)이 있습니다(논리명 '$logical'). 수동 복원이 필요합니다.")
            }
        }

        $moves += "MOVE N'$logical' TO N'$dataRoot/$fileName'"
    }

    if ($moves.Count -eq 0) { throw '백업에서 복원할 파일 정보를 읽지 못했습니다.' }
    return ($moves -join ",`n")
}


# ═══════════════════════════════════════════════════════════════════════════
#  Restore-OneInstance : 인스턴스 "하나"를 복원하는 실제 절차.
#  성공하면 { File; DB } 를 돌려주고, 어느 단계든 실패하면 오류(throw)를 냅니다.
# ═══════════════════════════════════════════════════════════════════════════
function Restore-OneInstance {
    param(
        [Parameter(Mandatory)][pscustomobject]$Instance,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$StagingDir,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$Stamp,
        [string]$BackupFile,
        [switch]$NoRecovery
    )

    $container = $Instance.Name

    # 1) 컨테이너 실행 여부 확인
    if (-not (Test-ContainerRunning -Container $container)) {
        throw '컨테이너가 실행 중이 아닙니다.'
    }

    # 2) 복원할 .bak 결정
    $src = Resolve-BackupFile -Instance $Instance -Database $Database -BackupRoot $BackupRoot -BackupFile $BackupFile
    $sizeMB = [math]::Round($src.Length / 1MB, 1)
    Write-Host ("  대상 백업: {0} ({1} MB)" -f $src.FullName, $sizeMB) -ForegroundColor DarkGray

    # 3) 컨테이너 임시 폴더로 복사
    $remoteBak = "$StagingDir/restore_$Stamp.bak"
    docker exec $container mkdir -p $StagingDir 2>$null | Out-Null
    & docker cp "$($src.FullName)" "${container}:$remoteBak"
    if ($LASTEXITCODE -ne 0) { throw 'docker cp (컨테이너로 복사) 실패' }

    try {
        # 4) 논리 파일명 → WITH MOVE 절 구성
        $moveClauses = Get-MoveClauses -Container $container -RemoteBak $remoteBak -Database $Database

        # 5) 복원 실행 (기존 DB 있으면 연결을 끊고 덮어씀)
        #    RECOVERY : 복원 후 즉시 사용 가능 / NORECOVERY : 추가 복원 대기(RESTORING)
        $recovery = if ($NoRecovery) { 'NORECOVERY' } else { 'RECOVERY' }
        Write-Host '  복원 실행 중...' -ForegroundColor DarkGray
        $restore = Invoke-Sql -Container $container -LoginTimeout 30 -Query @"
SET NOCOUNT ON;
IF DB_ID(N'$Database') IS NOT NULL
    ALTER DATABASE [$Database] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE [$Database] FROM DISK = N'$remoteBak'
WITH REPLACE, $recovery, STATS = 10,
$moveClauses;
"@
        if (-not $restore.Success) { throw ("RESTORE 실패: {0}" -f $restore.Output) }
    }
    finally {
        # 6) 컨테이너 안 임시 파일 정리 (성공/실패 무관)
        docker exec $container rm -f $remoteBak 2>$null | Out-Null
    }

    $state = if ($NoRecovery) { 'RESTORING(대기)' } else { 'ONLINE' }
    Write-Host ("  완료: {0} → {1}" -f $Database, $state) -ForegroundColor Green
    return [pscustomobject]@{ File = $src.Name; DB = $Database }
}


# ═══════════════════════════════════════════════════════════════════════════
#  여기서부터 메인 흐름
# ═══════════════════════════════════════════════════════════════════════════

Assert-Docker
$config = Read-DotEnv

# ── 설정 해석 (규칙: 명령줄 인자가 있으면 그것을, 없으면 .env 값을 사용) ──────
if (-not $Database)   { $Database   = $config['BACKUP_DATABASE'] }
if (-not $BackupRoot) { $BackupRoot = $config['BACKUP_ROOT'] }
$stagingDir = $StagingDir
if (-not $stagingDir) { $stagingDir = $config['BACKUP_STAGING_DIR'] }
if (-not $stagingDir) { $stagingDir = '/var/opt/mssql/backup' }   # 최종 기본값

# 꼭 필요한 값이 비어 있으면 여기서 친절히 알려 주고 멈춥니다.
if (-not $Database) {
    throw "DB 이름이 없습니다. .env 의 BACKUP_DATABASE 를 채우거나 -Database <이름> 을 지정하세요."
}
if (-not $BackupRoot) {
    throw '.env 에 BACKUP_ROOT 가 없습니다.'
}

# 대상 인스턴스 목록
$instances = Get-TargetInstances -Service $Service

# -BackupFile 은 한 파일을 뜻하므로, 여러 인스턴스에 동시에 쓰면 모호합니다.
if ($BackupFile -and @($instances).Count -ne 1) {
    throw '-BackupFile 은 -Service 로 인스턴스를 정확히 하나만 지정했을 때만 쓸 수 있습니다.'
}

# 파일 이름(임시)에 쓸 시각
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

Write-Host "`n=== 복원 시작 ===" -ForegroundColor Cyan
Write-Host ("  DB       : {0}" -f $Database)
Write-Host ("  대상     : {0} 개 인스턴스" -f @($instances).Count)
Write-Host ("  백업 위치: {0}" -f $BackupRoot)
Write-Host ("  모드     : {0}" -f $(if ($NoRecovery) { 'NORECOVERY (추가 복원 대기)' } else { 'RECOVERY (즉시 사용)' }))

# ── 파괴적 작업이므로 한 번 확인받습니다. ────────────────────────────────────
Write-Host "`n대상 DB 를 덮어씁니다 (기존 데이터는 사라집니다):" -ForegroundColor Yellow
$instances | ForEach-Object { Write-Host ("  - {0}  ←  {1}" -f $_.Name, $Database) }
if (-not $Force) {
    $answer = Read-Host "`n계속하시겠습니까? (y/N)"
    if ($answer -notmatch '^[Yy]$') {
        Write-Host '취소했습니다.' -ForegroundColor DarkGray
        return
    }
}

# ── 인스턴스별로 복원 (하나 실패해도 나머지는 계속) ──────────────────────────
$results = @()
foreach ($instance in $instances) {
    $row = [pscustomobject]@{
        Instance = $instance.Name
        Result   = ''
        File     = ''
        Detail   = ''
    }

    Write-Host ("`n--- {0} ---" -f $instance.Name) -ForegroundColor Cyan
    try {
        $info = Restore-OneInstance -Instance $instance -Database $Database `
                    -StagingDir $stagingDir -BackupRoot $BackupRoot -Stamp $stamp `
                    -BackupFile $BackupFile -NoRecovery:$NoRecovery

        $row.Result = 'OK'
        $row.File   = $info.File
    }
    catch {
        $row.Result = 'FAIL'
        $row.Detail = $_.Exception.Message
        Write-Host ("  실패: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    $results += $row
}

# ── 요약 ────────────────────────────────────────────────────────────────────
Write-Host "`n=== 복원 결과 ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$failed = @($results | Where-Object { $_.Result -eq 'FAIL' })
if ($failed.Count -gt 0) {
    Write-Host ("실패 {0}건: {1}" -f $failed.Count, (($failed.Instance) -join ', ')) -ForegroundColor Red
    exit 1   # 스케줄러가 실패를 감지할 수 있도록 0 이 아닌 코드로 종료
}

Write-Host ("전체 {0}건 복원 성공." -f @($results).Count) -ForegroundColor Green
