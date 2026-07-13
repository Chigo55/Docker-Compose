#Requires -Version 5.1
<#
.SYNOPSIS
    모든(또는 지정한) 인스턴스에서 같은 이름의 DB 를 백업합니다.

.DESCRIPTION
    "안전한 백업"을 위해, 파일을 직접 복사하지 않고 SQL Server 엔진에게
    BACKUP DATABASE 를 시킵니다. (실행 중인 인스턴스의 .mdf 파일을 그냥 복사하면
    손상된 사본이 나옵니다. 그래서 반드시 이 방식을 씁니다.)

    한 인스턴스에 대한 처리 순서:
      1) 컨테이너가 실행 중인지 + DB 가 존재하고 ONLINE 인지 확인
      2) 컨테이너 안 임시 폴더에 BACKUP DATABASE 실행
      3) (-Verify 시) RESTORE VERIFYONLY 로 백업 파일 무결성 검증
      4) docker cp 로 백업 파일을 호스트로 복사
      5) 컨테이너 안 임시 파일 삭제

    저장 위치:  <BACKUP_ROOT>\<컨테이너명>\<DB>_<yyyyMMdd_HHmmss>.bak

    한 인스턴스가 실패해도 나머지는 계속 진행하고, 마지막에 요약 표를 냅니다.
    실패가 하나라도 있으면 종료 코드 1 을 돌려주므로, 작업 스케줄러가 실패를 감지할 수 있습니다.

.EXAMPLE
    .\scripts\backup.ps1 -Database MyDb
    MyDb 를 모든 인스턴스에서 백업합니다.

.EXAMPLE
    .\scripts\backup.ps1
    .env 의 BACKUP_DATABASE 에 적힌 DB 를 백업합니다.

.EXAMPLE
    .\scripts\backup.ps1 -Service db2019c,db2022e
    지정한 인스턴스에서만 백업합니다.

.EXAMPLE
    .\scripts\backup.ps1 -Verify
    백업 직후 무결성까지 검증합니다.

.EXAMPLE
    .\scripts\backup.ps1 -CopyOnly
    기존 백업 체인에 영향을 주지 않는 복사 전용 백업을 합니다.

.EXAMPLE
    .\scripts\backup.ps1 -RetentionDays 0
    오래된 백업 자동 삭제를 하지 않습니다.
#>
[CmdletBinding()]
param(
    [string]$Database,            # 백업할 DB 이름 (안 주면 .env 의 BACKUP_DATABASE 사용)
    [string[]]$Service = @(),     # 비우면 전체, 지정하면 그 인스턴스만
    [string]$BackupRoot,          # 저장 최상위 폴더 (안 주면 .env 의 BACKUP_ROOT 사용)
    [int]$RetentionDays = -1,     # 보관 일수. -1 이면 .env 값 사용, 0 이면 자동 삭제 안 함
    [switch]$CopyOnly,            # 붙이면: 백업 체인에 영향 없는 복사 전용 백업
    [switch]$Verify,              # 붙이면: 백업 후 무결성 검증
    [switch]$NoCompression        # 붙이면: 압축 없이 백업
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot


# ═══════════════════════════════════════════════════════════════════════════
#  Backup-OneInstance : 인스턴스 "하나"를 백업하는 실제 절차.
#  성공하면 { File; SizeMB } 를 돌려주고, 어느 단계든 실패하면 오류(throw)를 냅니다.
#  (성공/실패 집계는 아래 메인 반복문이 담당합니다.)
# ═══════════════════════════════════════════════════════════════════════════
function Backup-OneInstance {
    param(
        [Parameter(Mandatory)][pscustomobject]$Instance,   # 대상 인스턴스 (Name/Port/DataDir 등)
        [Parameter(Mandatory)][string]$Database,           # 백업할 DB 이름
        [Parameter(Mandatory)][string]$StagingDir,         # 컨테이너 안 임시 저장 경로
        [Parameter(Mandatory)][string]$BackupRoot,         # 호스트 저장 최상위 폴더
        [Parameter(Mandatory)][string]$Stamp,              # 파일 이름에 붙일 시각 문자열
        [switch]$Verify,
        [switch]$CopyOnly,
        [switch]$NoCompression
    )

    $container = $Instance.Name

    # 1) 컨테이너 실행 여부 확인
    if (-not (Test-ContainerRunning -Container $container)) {
        throw '컨테이너가 실행 중이 아닙니다.'
    }

    # 1-b) DB 가 존재하고 ONLINE 상태인지 확인
    $check = Invoke-Sql -Container $container -Query @"
SET NOCOUNT ON;
SELECT state_desc FROM sys.databases WHERE name = N'$Database';
"@
    if (-not $check.Success)          { throw ("SQL 연결 실패: {0}" -f $check.Output) }
    if (-not $check.Output)           { throw ("DB '{0}' 가 없습니다." -f $Database) }
    if ($check.Output -ne 'ONLINE')   { throw ("DB 상태가 ONLINE 이 아닙니다: {0}" -f $check.Output) }

    # 2) 컨테이너 안에서 백업 실행
    $fileName  = "{0}_{1}.bak" -f $Database, $Stamp   # 예: MyDb_20260713_020000.bak
    $remoteBak = "$StagingDir/$fileName"              # 컨테이너 안 경로

    docker exec $container mkdir -p $StagingDir 2>$null | Out-Null

    # BACKUP DATABASE 에 붙일 옵션들을 조립합니다.
    #  INIT     : 같은 파일이 있으면 덮어씀
    #  CHECKSUM : 백업하며 체크섬 기록 (무결성 확인용)
    #  FORMAT   : 미디어를 새로 초기화
    #  STATS=10 : 진행률을 10% 단위로 출력
    $withOptions = @('INIT', 'CHECKSUM', 'FORMAT', 'STATS = 10')
    if (-not $NoCompression) { $withOptions += 'COMPRESSION' }   # 압축(용량 절약)
    if ($CopyOnly)           { $withOptions += 'COPY_ONLY' }     # 백업 체인 미영향

    Write-Host '  백업 실행 중...' -ForegroundColor DarkGray
    $backup = Invoke-Sql -Container $container -Query @"
SET NOCOUNT ON;
BACKUP DATABASE [$Database] TO DISK = N'$remoteBak'
WITH $($withOptions -join ', '), NAME = N'$Database full backup';
"@
    if (-not $backup.Success) { throw ("BACKUP 실패: {0}" -f $backup.Output) }

    # 3) (선택) 무결성 검증
    if ($Verify) {
        Write-Host '  검증 중 (RESTORE VERIFYONLY)...' -ForegroundColor DarkGray
        $verify = Invoke-Sql -Container $container -Query "RESTORE VERIFYONLY FROM DISK = N'$remoteBak' WITH CHECKSUM;"
        if (-not $verify.Success) { throw ("검증 실패: {0}" -f $verify.Output) }
    }

    # 4) 호스트로 복사  (<BACKUP_ROOT>\<컨테이너명>\<파일>)
    $hostDir = Join-Path $BackupRoot $container
    if (-not (Test-Path $hostDir)) { New-Item -ItemType Directory -Path $hostDir -Force | Out-Null }
    $hostBak = Join-Path $hostDir $fileName

    & docker cp "${container}:$remoteBak" "$hostBak"
    if ($LASTEXITCODE -ne 0)       { throw 'docker cp (호스트로 복사) 실패' }
    if (-not (Test-Path $hostBak)) { throw '복사된 파일을 찾을 수 없습니다.' }

    # 5) 컨테이너 안 임시 파일 정리
    docker exec $container rm -f $remoteBak 2>$null | Out-Null

    # 결과 정보를 돌려줍니다.
    $sizeMB = [math]::Round((Get-Item $hostBak).Length / 1MB, 1)
    Write-Host ("  완료: {0} ({1} MB)" -f $hostBak, $sizeMB) -ForegroundColor Green
    return [pscustomobject]@{ File = $fileName; SizeMB = $sizeMB }
}


# ═══════════════════════════════════════════════════════════════════════════
#  여기서부터 메인 흐름
# ═══════════════════════════════════════════════════════════════════════════

Assert-Docker
$config = Read-DotEnv

# ── 설정 해석 (규칙: 명령줄 인자가 있으면 그것을, 없으면 .env 값을 사용) ──────
if (-not $Database)   { $Database   = $config['BACKUP_DATABASE'] }
if (-not $BackupRoot) { $BackupRoot = $config['BACKUP_ROOT'] }
if ($RetentionDays -lt 0) {
    $RetentionDays = if ($config['BACKUP_RETENTION_DAYS']) { [int]$config['BACKUP_RETENTION_DAYS'] } else { 0 }
}
$stagingDir = $config['BACKUP_STAGING_DIR']
if (-not $stagingDir) { $stagingDir = '/var/opt/mssql/backup' }   # .env 에 없을 때 기본값

# 꼭 필요한 값이 비어 있으면 여기서 친절히 알려 주고 멈춥니다.
if (-not $Database) {
    throw "DB 이름이 없습니다. .env 의 BACKUP_DATABASE 를 채우거나 -Database <이름> 을 지정하세요."
}
if (-not $BackupRoot) {
    throw '.env 에 BACKUP_ROOT 가 없습니다.'
}

# 대상 인스턴스 목록
$instances = Get-TargetInstances -Service $Service

# 파일 이름에 쓸 시각 (모든 인스턴스가 같은 시각 문자열을 공유합니다)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

Write-Host "`n=== 백업 시작 ===" -ForegroundColor Cyan
Write-Host ("  DB       : {0}" -f $Database)
Write-Host ("  대상     : {0} 개 인스턴스" -f @($instances).Count)
Write-Host ("  저장 위치: {0}" -f $BackupRoot)
Write-Host ("  보관     : {0}" -f $(if ($RetentionDays -gt 0) { "$RetentionDays 일" } else { '자동 삭제 안 함' }))

# ── 인스턴스별로 백업 (하나 실패해도 나머지는 계속) ──────────────────────────
$results = @()
foreach ($instance in $instances) {
    # 결과 표에 넣을 한 줄. 성공/실패에 따라 아래에서 채웁니다.
    $row = [pscustomobject]@{
        Instance = $instance.Name
        Result   = ''
        Size     = ''
        File     = ''
        Detail   = ''
    }

    Write-Host ("`n--- {0} ---" -f $instance.Name) -ForegroundColor Cyan
    try {
        $info = Backup-OneInstance -Instance $instance -Database $Database `
                    -StagingDir $stagingDir -BackupRoot $BackupRoot -Stamp $stamp `
                    -Verify:$Verify -CopyOnly:$CopyOnly -NoCompression:$NoCompression

        $row.Result = 'OK'
        $row.Size   = "$($info.SizeMB) MB"
        $row.File   = $info.File
    }
    catch {
        # 이 인스턴스만 실패로 기록하고 다음 인스턴스로 넘어갑니다.
        $row.Result = 'FAIL'
        $row.Detail = $_.Exception.Message
        Write-Host ("  실패: {0}" -f $_.Exception.Message) -ForegroundColor Red
    }

    $results += $row
}

# ── 보관 기간이 지난 오래된 백업 파일 정리 ──────────────────────────────────
if ($RetentionDays -gt 0) {
    $cutoff  = (Get-Date).AddDays(-$RetentionDays)   # 이 시각보다 오래된 파일이 삭제 대상
    $deleted = 0
    foreach ($instance in $instances) {
        $hostDir = Join-Path $BackupRoot $instance.Name
        if (-not (Test-Path $hostDir)) { continue }

        Get-ChildItem -Path $hostDir -Filter '*.bak' -File |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                Remove-Item $_.FullName -Force
                Write-Host ("  [삭제] {0}" -f $_.FullName) -ForegroundColor DarkGray
                $deleted++
            }
    }
    if ($deleted -gt 0) {
        Write-Host ("`n{0}일 이전 백업 {1}개 삭제" -f $RetentionDays, $deleted) -ForegroundColor DarkGray
    }
}

# ── 요약 ────────────────────────────────────────────────────────────────────
Write-Host "`n=== 백업 결과 ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$failed = @($results | Where-Object { $_.Result -eq 'FAIL' })
if ($failed.Count -gt 0) {
    Write-Host ("실패 {0}건: {1}" -f $failed.Count, (($failed.Instance) -join ', ')) -ForegroundColor Red
    exit 1   # 스케줄러가 실패를 감지할 수 있도록 0 이 아닌 코드로 종료
}

Write-Host ("전체 {0}건 성공." -f @($results).Count) -ForegroundColor Green
