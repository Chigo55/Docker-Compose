#Requires -Version 5.1
<#
.SYNOPSIS
    백업(.bak)을 인스턴스에 복원(RESTORE)합니다. backup.ps1 의 짝입니다.

.DESCRIPTION
    "안전한 복원"을 위해 파일을 직접 붙이지 않고 SQL Server 엔진에게
    RESTORE DATABASE 를 시킵니다. 사람이 신경 쓰기 번거로운 부분을 자동화합니다.

      · 백업 파일 자동 선택 : <BACKUP_ROOT>\<컨테이너명>\<DB>_*.bak 중 가장 최신 파일
      · 체인 복원(-Chain)   : 최신 전체(.bak)→차등(.dif)→로그(.trn) 를 자동으로 이어
                              앞 파일은 NORECOVERY, 마지막만 RECOVERY 로 적용(시점복구)
      · 논리 파일 자동 이동 : RESTORE FILELISTONLY 로 백업 안의 논리 파일명을 읽어
                              WITH MOVE 절을 자동으로 만들어 /var/opt/mssql/data 로 배치
      · 버전 자동 판별      : 2019/2022 sqlcmd 경로를 컨테이너에서 실제 확인(_common.ps1)
      · 활성 연결 정리      : 기존 DB 가 있으면 SINGLE_USER 로 연결을 끊고 덮어씁니다.
      · 다른 이름 복원(-AsDatabase) : 백업 속 DB 를 다른 이름으로 복원합니다.
                              물리 파일(.mdf/.ldf)도 그 이름으로 배치해 원본과 공존할 수 있습니다.

    한 인스턴스에 대한 처리 순서:
      1) 컨테이너 실행 확인
      2) 복원할 파일 결정
         · 기본        : 해당 컨테이너 폴더의 최신 .bak 하나
         · -Chain      : 최신 전체(.bak)→차등(.dif)→로그(.trn) 체인
         · -BackupFile : 지정한 파일 하나
      3) (체인의 파일마다) docker cp 로 컨테이너 임시 폴더에 복사
      4) 전체 백업은 RESTORE FILELISTONLY 로 논리 파일명/유형(D/L) 파악 → WITH MOVE 구성
      5) (기존 DB 존재 시) SINGLE_USER 로 전환 후 RESTORE ... WITH REPLACE.
         체인이면 전체·차등·앞선 로그는 NORECOVERY, 마지막 파일만 RECOVERY.
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

.EXAMPLE
    .\scripts\restore.ps1 -Service db2019c -Database MyDb -Chain
    최신 전체→차등→로그 백업을 순서대로 이어 복원합니다(가능한 최신 시점까지).

.EXAMPLE
    .\scripts\restore.ps1 -Service db2022b -Database MyDb -AsDatabase MyDb_staging
    MyDb 백업을 db2022b 에 MyDb_staging 이라는 다른 이름으로 복원합니다(원본과 공존).
#>
[CmdletBinding()]
param(
    [string]$Database,             # 복원할 DB 이름 (안 주면 .env 의 BACKUP_DATABASE 사용)
    [string]$AsDatabase,           # 다른 이름으로 복원 (백업 원본과 다른 DB 로). 물리 파일도 이 이름으로
    [string[]]$Service = @(),      # 비우면 전체, 지정하면 그 인스턴스만
    [string]$BackupRoot,           # 백업 저장 최상위 폴더 (안 주면 .env 의 BACKUP_ROOT 사용)
    [string]$BackupFile,           # 특정 .bak 경로 직접 지정 (단일 -Service 와 함께)
    [string]$StagingDir,           # 컨테이너 안 임시 경로 (안 주면 .env 의 BACKUP_STAGING_DIR)
    [switch]$NoRecovery,           # 붙이면: WITH NORECOVERY (추가 로그 복원 대기)
    [switch]$Chain,                # 붙이면: 최신 전체→차등→로그 체인을 자동으로 이어 복원
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
#  Get-RestoreChain : 최신 복구 체인(전체→차등→로그)을 이룰 파일들을 순서대로 돌려줍니다.
#    1) 가장 최근 전체 백업(.bak)
#    2) 그 전체 이후의 가장 최근 차등(.dif) — 있으면
#    3) 차등(없으면 전체) 이후의 모든 로그(.trn) — 시각 오름차순
#  전체보다 오래된, 또는 차등보다 오래된 로그는 이미 반영됐거나 겹치므로 제외합니다.
#  ※ 파일 수정시각으로 체인을 추정합니다. 표준 순서로 백업했다면 맞아떨어지며,
#    LSN 이 어긋나면 실제 RESTORE 단계에서 SQL Server 가 오류로 알려 줍니다.
# ═══════════════════════════════════════════════════════════════════════════
function Get-RestoreChain {
    param(
        [Parameter(Mandatory)][pscustomobject]$Instance,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$BackupRoot
    )

    $hostDir = Join-Path $BackupRoot $Instance.Name
    if (-not (Test-Path $hostDir)) { throw ("백업 폴더가 없습니다: {0}" -f $hostDir) }

    # 1) 기준이 될 최신 전체 백업
    $full = Get-ChildItem -Path $hostDir -Filter ("{0}_*.bak" -f $Database) -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $full) { throw ("체인의 기준이 될 전체 백업(.bak)이 없습니다: {0}\{1}_*.bak" -f $hostDir, $Database) }

    $chain = [System.Collections.Generic.List[object]]::new()
    $chain.Add($full)

    # 2) 전체 이후의 최신 차등
    $diff = Get-ChildItem -Path $hostDir -Filter ("{0}_*.dif" -f $Database) -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $full.LastWriteTime } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($diff) { $chain.Add($diff) }

    # 3) 차등(있으면)·전체 이후의 모든 로그를 시각 오름차순으로
    $baseTime = if ($diff) { $diff.LastWriteTime } else { $full.LastWriteTime }
    Get-ChildItem -Path $hostDir -Filter ("{0}_*.trn" -f $Database) -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -gt $baseTime } |
        Sort-Object LastWriteTime |
        ForEach-Object { $chain.Add($_) }

    return @($chain)
}


# ═══════════════════════════════════════════════════════════════════════════
#  Get-MoveClauses : 백업 안의 논리 파일명을 읽어 WITH MOVE 절을 만듭니다.
#  RESTORE FILELISTONLY 결과에서 LogicalName(1번째)·Type(3번째) 컬럼을 사용합니다.
#    Type 'D' = 데이터, 'L' = 로그. 그 외(F/S 등)는 자동 처리하지 않고 중단합니다.
#  대상 경로는 컨테이너의 데이터 폴더(/var/opt/mssql/data)로 통일합니다.
#  물리 파일 이름은 $TargetName(= 복원 대상 DB 이름)을 씁니다. -AsDatabase 로 다른
#  이름에 복원할 때 원본 DB 의 파일을 덮어쓰지 않도록 하기 위함입니다.
# ═══════════════════════════════════════════════════════════════════════════
function Get-MoveClauses {
    param(
        [Parameter(Mandatory)][string]$Container,
        [Parameter(Mandatory)][string]$RemoteBak,
        [Parameter(Mandatory)][string]$TargetName   # 물리 파일 이름 베이스(= 복원 대상 DB 이름)
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
                $fileName = if ($dataN -eq 1) { "$TargetName.mdf" } else { "${TargetName}_$dataN.ndf" }
            }
            'L' {
                $logN++
                $fileName = if ($logN -eq 1) { "${TargetName}_log.ldf" } else { "${TargetName}_log_$logN.ldf" }
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
#  Restore-OneInstance : 인스턴스 "하나"를 복원하는 실제 절차(체인이면 여러 파일).
#  성공하면 { File; DB; Count } 를 돌려주고, 어느 단계든 실패하면 오류(throw)를 냅니다.
# ═══════════════════════════════════════════════════════════════════════════
function Restore-OneInstance {
    param(
        [Parameter(Mandatory)][pscustomobject]$Instance,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$StagingDir,
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$Stamp,
        [string]$BackupFile,
        [string]$AsDatabase,
        [switch]$Chain,
        [switch]$NoRecovery
    )

    $container = $Instance.Name

    # 백업 파일은 원본 이름($Database)으로 찾고, 실제 복원 대상 이름은 $targetDb 입니다.
    # -AsDatabase 를 주면 다른 이름으로 복원하며, 물리 파일도 그 이름으로 배치합니다.
    $targetDb = if ($AsDatabase) { $AsDatabase } else { $Database }

    # 1) 컨테이너 실행 여부 확인
    if (-not (Test-ContainerRunning -Container $container)) {
        throw '컨테이너가 실행 중이 아닙니다.'
    }

    # 2) 복원할 파일 목록(체인) 결정
    #    · -BackupFile : 지정한 그 파일 하나
    #    · -Chain      : 최신 전체→차등→로그 자동 연결
    #    · (기본)      : 해당 폴더의 최신 전체 백업 하나 (기존 동작 그대로)
    if ($BackupFile) {
        $chain = @(Resolve-BackupFile -Instance $Instance -Database $Database -BackupRoot $BackupRoot -BackupFile $BackupFile)
    } elseif ($Chain) {
        $chain = Get-RestoreChain -Instance $Instance -Database $Database -BackupRoot $BackupRoot
    } else {
        $chain = @(Resolve-BackupFile -Instance $Instance -Database $Database -BackupRoot $BackupRoot)
    }

    Write-Host ("  복원 체인: {0}개 파일" -f $chain.Count) -ForegroundColor DarkGray
    $chain | ForEach-Object {
        Write-Host ("    - {0} ({1} MB)" -f $_.Name, [math]::Round($_.Length / 1MB, 1)) -ForegroundColor DarkGray
    }

    # 3) 파일마다: 컨테이너로 복사 → RESTORE → 임시 파일 정리
    #    첫 파일(전체)만 WITH MOVE + REPLACE + SINGLE_USER. 마지막 파일만 RECOVERY.
    #    (-NoRecovery 면 마지막까지 NORECOVERY 로 두어 이후 수동 로그 복원을 이어갈 수 있게 합니다.)
    docker exec $container mkdir -p $StagingDir 2>$null | Out-Null

    for ($i = 0; $i -lt $chain.Count; $i++) {
        $file     = $chain[$i]
        $isFirst  = ($i -eq 0)
        $isLast   = ($i -eq ($chain.Count - 1))
        $recovery = if ($isLast -and -not $NoRecovery) { 'RECOVERY' } else { 'NORECOVERY' }

        $remoteBak = "$StagingDir/restore_${Stamp}_$i.bak"
        & docker cp "$($file.FullName)" "${container}:$remoteBak"
        if ($LASTEXITCODE -ne 0) { throw ("docker cp (컨테이너로 복사) 실패: {0}" -f $file.Name) }

        try {
            if ($isFirst) {
                # 전체 백업: 논리 파일명 → WITH MOVE 구성(물리 파일은 대상 이름으로),
                #            기존 대상 DB 가 있으면 연결 끊고 덮어씀.
                $moveClauses = Get-MoveClauses -Container $container -RemoteBak $remoteBak -TargetName $targetDb
                Write-Host ("  [1/{0}] 전체 복원: {1} → [{2}] ({3})" -f $chain.Count, $file.Name, $targetDb, $recovery) -ForegroundColor DarkGray
                $sql = @"
SET NOCOUNT ON;
IF DB_ID(N'$targetDb') IS NOT NULL
    ALTER DATABASE [$targetDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
RESTORE DATABASE [$targetDb] FROM DISK = N'$remoteBak'
WITH REPLACE, $recovery, STATS = 10,
$moveClauses;
"@
            } else {
                # 차등(.dif)은 RESTORE DATABASE, 로그(.trn)는 RESTORE LOG. 둘 다 MOVE 불필요.
                $ext    = $file.Extension.ToLower()
                $target = if ($ext -eq '.trn') { 'LOG' } else { 'DATABASE' }
                $label  = if ($ext -eq '.trn') { '로그' } elseif ($ext -eq '.dif') { '차등' } else { '추가' }
                Write-Host ("  [{0}/{1}] {2} 복원: {3} ({4})" -f ($i + 1), $chain.Count, $label, $file.Name, $recovery) -ForegroundColor DarkGray
                $sql = @"
SET NOCOUNT ON;
RESTORE $target [$targetDb] FROM DISK = N'$remoteBak'
WITH $recovery, STATS = 10;
"@
            }

            $r = Invoke-Sql -Container $container -LoginTimeout 30 -Query $sql
            if (-not $r.Success) { throw ("RESTORE 실패({0}): {1}" -f $file.Name, $r.Output) }
        }
        finally {
            # 컨테이너 안 임시 파일 정리 (성공/실패 무관)
            docker exec $container rm -f $remoteBak 2>$null | Out-Null
        }
    }

    $state  = if ($NoRecovery) { 'RESTORING(대기)' } else { 'ONLINE' }
    $asNote = if ($AsDatabase) { " (원본 $Database)" } else { '' }
    Write-Host ("  완료: {0}{1} → {2}  ({3}개 파일)" -f $targetDb, $asNote, $state, $chain.Count) -ForegroundColor Green
    return [pscustomobject]@{ File = $chain[0].Name; DB = $targetDb; Count = $chain.Count }
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

# -BackupFile 과 -Chain 은 서로 다른 파일 선택 방식이라 함께 쓸 수 없습니다.
if ($BackupFile -and $Chain) {
    throw '-BackupFile 과 -Chain 은 함께 쓸 수 없습니다. 하나만 지정하세요.'
}

# -BackupFile 은 한 파일을 뜻하므로, 여러 인스턴스에 동시에 쓰면 모호합니다.
if ($BackupFile -and @($instances).Count -ne 1) {
    throw '-BackupFile 은 -Service 로 인스턴스를 정확히 하나만 지정했을 때만 쓸 수 있습니다.'
}

# 파일 이름(임시)에 쓸 시각
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

# 실제 복원 대상 DB 이름 (다른 이름 복원 시 -AsDatabase, 아니면 원본과 동일)
$targetDb = if ($AsDatabase) { $AsDatabase } else { $Database }

Write-Host "`n=== 복원 시작 ===" -ForegroundColor Cyan
Write-Host ("  DB       : {0}{1}" -f $Database, $(if ($AsDatabase) { " → $AsDatabase (다른 이름)" } else { '' }))
Write-Host ("  대상     : {0} 개 인스턴스" -f @($instances).Count)
Write-Host ("  백업 위치: {0}" -f $BackupRoot)
Write-Host ("  모드     : {0}" -f $(if ($NoRecovery) { 'NORECOVERY (추가 복원 대기)' } else { 'RECOVERY (즉시 사용)' }))
Write-Host ("  체인     : {0}" -f $(if ($Chain) { '예 (전체→차등→로그 자동 연결)' } else { '아니오' }))

# ── 파괴적 작업이므로 한 번 확인받습니다. ────────────────────────────────────
Write-Host "`n대상 DB 를 덮어씁니다 (기존 데이터는 사라집니다):" -ForegroundColor Yellow
$instances | ForEach-Object { Write-Host ("  - {0}: [{1}]  ←  {2} 백업" -f $_.Name, $targetDb, $Database) }
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
        $info = Restore-OneInstance -Instance $instance -Database $Database -AsDatabase $AsDatabase `
                    -StagingDir $stagingDir -BackupRoot $BackupRoot -Stamp $stamp `
                    -BackupFile $BackupFile -Chain:$Chain -NoRecovery:$NoRecovery

        $row.Result = 'OK'
        $row.File   = if ($info.Count -gt 1) { '{0} (+{1})' -f $info.File, ($info.Count - 1) } else { $info.File }
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
