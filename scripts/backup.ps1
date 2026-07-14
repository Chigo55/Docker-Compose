#Requires -Version 5.1
<#
.SYNOPSIS
    모든(또는 지정한) 인스턴스에서 같은 이름의 DB 를 백업합니다.

.DESCRIPTION
    "안전한 백업"을 위해, 파일을 직접 복사하지 않고 SQL Server 엔진에게
    BACKUP 을 시킵니다. (실행 중인 인스턴스의 .mdf 파일을 그냥 복사하면
    손상된 사본이 나옵니다. 그래서 반드시 이 방식을 씁니다.)

    -Type 으로 세 가지 백업을 지원합니다(표준 복구 전략: 전체 + 차등 + 로그):
      · Full (기본) : 전체 백업.            BACKUP DATABASE ...            → .bak
      · Diff        : 차등 백업(직전 전체 이후 변경분). ... WITH DIFFERENTIAL → .dif
      · Log         : 트랜잭션 로그 백업.   BACKUP LOG ...                 → .trn
    Diff 는 기준이 될 전체 백업이, Log 는 복구 모델 FULL(또는 BULK_LOGGED)이 먼저
    있어야 합니다. 복구 모델이 SIMPLE 인 DB 의 로그 백업은 건너뜁니다(SKIP, 실패 아님).

    한 인스턴스에 대한 처리 순서:
      1) 컨테이너가 실행 중인지 + DB 가 존재하고 ONLINE 인지 확인
         (Log 백업이면 복구 모델도 확인 — SIMPLE 이면 건너뜀)
      2) 컨테이너 안 임시 폴더에 BACKUP 실행
      3) (-Verify 시) RESTORE VERIFYONLY 로 백업 파일 무결성 검증
      4) docker cp 로 백업 파일을 호스트로 복사
      5) 컨테이너 안 임시 파일 삭제

    저장 위치:  <BACKUP_ROOT>\<컨테이너명>\<DB>_<yyyyMMdd_HHmmss>.<bak|dif|trn>

    보관(-RetentionDays): .bak/.dif/.trn 을 파일 수정시각 기준으로 함께 정리합니다.
    ※ 시각 기준이라 복구 체인(전체↔차등↔로그) 의존성은 고려하지 않습니다. 엄격한
      시점복구(PITR) 보관이 필요하면 -RetentionDays 0 으로 끄고 수동 관리하세요.

    한 인스턴스가 실패해도 나머지는 계속 진행하고, 마지막에 요약 표를 냅니다.
    실패가 하나라도 있으면 종료 코드 1 을 돌려주므로, 작업 스케줄러가 실패를 감지할 수 있습니다.

.EXAMPLE
    .\scripts\backup.ps1 -Database MyDb
    MyDb 를 모든 인스턴스에서 전체 백업합니다. (기본 -Type Full)

.EXAMPLE
    .\scripts\backup.ps1 -Database MyDb -Type Diff
    MyDb 의 차등 백업(직전 전체 백업 이후 변경분)을 만듭니다. (.dif)

.EXAMPLE
    .\scripts\backup.ps1 -Database MyDb -Type Log
    MyDb 의 트랜잭션 로그 백업을 만듭니다. 복구 모델이 FULL 이어야 합니다. (.trn)

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

.EXAMPLE
    .\scripts\backup.ps1 -Database MyDb -NotifyWebhook $env:TEAMS_WEBHOOK
    백업 후 결과 요약(성공/실패/건너뜀)을 Teams/Slack webhook 으로 보냅니다(무인 운영 알림).
#>
[CmdletBinding()]
param(
    [string]$Database,            # 백업할 DB 이름 (안 주면 .env 의 BACKUP_DATABASE 사용)
    [ValidateSet('Full', 'Diff', 'Log')]
    [string]$Type = 'Full',       # 백업 유형: Full 전체 / Diff 차등 / Log 트랜잭션 로그
    [string[]]$Service = @(),     # 비우면 전체, 지정하면 그 인스턴스만
    [string]$BackupRoot,          # 저장 최상위 폴더 (안 주면 .env 의 BACKUP_ROOT 사용)
    [int]$RetentionDays = -1,     # 보관 일수. -1 이면 .env 값 사용, 0 이면 자동 삭제 안 함
    [switch]$CopyOnly,            # 붙이면: 백업 체인에 영향 없는 복사 전용 백업
    [switch]$Verify,              # 붙이면: 백업 후 무결성 검증
    [switch]$NoCompression,       # 붙이면: 압축 없이 백업
    [string]$NotifyWebhook        # 값을 주면: 백업 요약을 이 webhook(Teams/Slack)으로 전송
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot


# ═══════════════════════════════════════════════════════════════════════════
#  Backup-OneInstance : 인스턴스 "하나"를 백업하는 실제 절차.
#  성공하면 { Skipped=$false; File; SizeMB }, 건너뛰면 { Skipped=$true; Reason } 을
#  돌려주고, 어느 단계든 실패하면 오류(throw)를 냅니다.
#  (성공/건너뜀/실패 집계는 아래 메인 반복문이 담당합니다.)
# ═══════════════════════════════════════════════════════════════════════════
function Backup-OneInstance {
    param(
        [Parameter(Mandatory)][pscustomobject]$Instance,   # 대상 인스턴스 (Name/Port/DataDir 등)
        [Parameter(Mandatory)][string]$Database,           # 백업할 DB 이름
        [Parameter(Mandatory)][ValidateSet('Full', 'Diff', 'Log')][string]$Type,   # 백업 유형
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

    # 1-b) DB 가 존재하고 ONLINE 인지 (+ Log 백업이면 복구 모델도) 확인.
    #      결과는 'state_desc|recovery_model_desc' 한 줄로 받아 나눠 읽습니다.
    $check = Invoke-Sql -Container $container -Query @"
SET NOCOUNT ON;
SELECT state_desc + N'|' + recovery_model_desc FROM sys.databases WHERE name = N'$Database';
"@
    if (-not $check.Success) { throw ("SQL 연결 실패: {0}" -f $check.Output) }
    if (-not $check.Output)  { throw ("DB '{0}' 가 없습니다." -f $Database) }

    $parts    = $check.Output -split '\|'
    $state    = $parts[0].Trim()
    $recovery = if ($parts.Count -gt 1) { $parts[1].Trim().ToUpper() } else { '' }
    if ($state -ne 'ONLINE') { throw ("DB 상태가 ONLINE 이 아닙니다: {0}" -f $state) }

    # 로그 백업은 복구 모델이 FULL/BULK_LOGGED 여야 의미가 있습니다. SIMPLE 이면 건너뜁니다.
    # (실패가 아니라 SKIP — 전 인스턴스 야간 로그 백업에서 SIMPLE DB 하나로 잡을 실패로 보지 않도록.)
    if ($Type -eq 'Log' -and $recovery -eq 'SIMPLE') {
        Write-Host '  건너뜀: 복구 모델이 SIMPLE 이라 로그 백업을 할 수 없습니다.' -ForegroundColor Yellow
        return [pscustomobject]@{ Skipped = $true; Reason = '복구 모델 SIMPLE (로그 백업 불가)'; File = ''; SizeMB = 0 }
    }

    # 2) 컨테이너 안에서 백업 실행
    #    유형별로 파일 확장자 · BACKUP 대상(DATABASE/LOG) · 추가 옵션이 달라집니다.
    $typeInfo = switch ($Type) {
        'Full' { @{ Ext = 'bak'; Target = 'DATABASE'; Extra = @();               Label = 'full backup' } }
        'Diff' { @{ Ext = 'dif'; Target = 'DATABASE'; Extra = @('DIFFERENTIAL'); Label = 'differential backup' } }
        'Log'  { @{ Ext = 'trn'; Target = 'LOG';      Extra = @();               Label = 'log backup' } }
    }

    $fileName  = "{0}_{1}.{2}" -f $Database, $Stamp, $typeInfo.Ext   # 예: MyDb_20260713_020000.bak
    $remoteBak = "$StagingDir/$fileName"                             # 컨테이너 안 경로

    docker exec $container mkdir -p $StagingDir 2>$null | Out-Null

    # BACKUP 에 붙일 옵션들을 조립합니다.
    #  DIFFERENTIAL : (Diff 만) 직전 전체 백업 이후 변경분만
    #  INIT     : 같은 파일이 있으면 덮어씀 (파일명이 시각별로 유일하므로 사실상 새 파일)
    #  CHECKSUM : 백업하며 체크섬 기록 (무결성 확인용)
    #  FORMAT   : 미디어를 새로 초기화
    #  STATS=10 : 진행률을 10% 단위로 출력
    $withOptions = @($typeInfo.Extra) + @('INIT', 'CHECKSUM', 'FORMAT', 'STATS = 10')
    if (-not $NoCompression) { $withOptions += 'COMPRESSION' }       # 압축(용량 절약)
    # COPY_ONLY 는 전체·로그에만 의미가 있습니다(차등에는 무시되므로 넣지 않습니다).
    if ($CopyOnly -and $Type -ne 'Diff') { $withOptions += 'COPY_ONLY' }   # 백업 체인 미영향

    Write-Host ("  백업 실행 중... ({0})" -f $Type) -ForegroundColor DarkGray
    $backup = Invoke-Sql -Container $container -Query @"
SET NOCOUNT ON;
BACKUP $($typeInfo.Target) [$Database] TO DISK = N'$remoteBak'
WITH $($withOptions -join ', '), NAME = N'$Database $($typeInfo.Label)';
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
    return [pscustomobject]@{ Skipped = $false; File = $fileName; SizeMB = $sizeMB }
}


# ═══════════════════════════════════════════════════════════════════════════
#  Send-BackupNotification : 백업 요약을 webhook 으로 보냅니다.
#  Teams·Slack 인커밍 webhook 모두 {"text": "..."} 페이로드를 받습니다.
#  알림 실패가 백업 결과(종료 코드)를 바꾸면 안 되므로, 실패해도 경고만 남깁니다.
# ═══════════════════════════════════════════════════════════════════════════
function Send-BackupNotification {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Message
    )
    try {
        $body  = @{ text = $Message } | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)   # 한글이 깨지지 않게 UTF-8 로 전송
        Invoke-RestMethod -Uri $Url -Method Post -ContentType 'application/json; charset=utf-8' -Body $bytes | Out-Null
        Write-Host '  webhook 알림 전송함.' -ForegroundColor DarkGray
    } catch {
        Write-Host ("  webhook 알림 실패(무시): {0}" -f $_.Exception.Message) -ForegroundColor Yellow
    }
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
Write-Host ("  유형     : {0}" -f $Type)
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
        $info = Backup-OneInstance -Instance $instance -Database $Database -Type $Type `
                    -StagingDir $stagingDir -BackupRoot $BackupRoot -Stamp $stamp `
                    -Verify:$Verify -CopyOnly:$CopyOnly -NoCompression:$NoCompression

        if ($info.Skipped) {
            $row.Result = 'SKIP'
            $row.Detail = $info.Reason
        } else {
            $row.Result = 'OK'
            $row.Size   = "$($info.SizeMB) MB"
            $row.File   = $info.File
        }
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

        # 세 유형(.bak/.dif/.trn)을 시각 기준으로 함께 정리합니다(체인 의존성 비인식 — 헤더 주석 참고).
        Get-ChildItem -Path $hostDir -File |
            Where-Object { $_.Extension -in '.bak', '.dif', '.trn' -and $_.LastWriteTime -lt $cutoff } |
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

$failed  = @($results | Where-Object { $_.Result -eq 'FAIL' })
$ok      = @($results | Where-Object { $_.Result -eq 'OK' })
$skipped = @($results | Where-Object { $_.Result -eq 'SKIP' })

# ── (선택) webhook 알림: 성공·실패 모두 요약을 보냅니다(무인 운영에서 결과 능동 확인). ──
# exit 1 보다 먼저 보내야 실패 시에도 알림이 나갑니다.
if ($NotifyWebhook) {
    $status  = if ($failed.Count -gt 0) { 'FAILED' } else { 'OK' }
    $summary = "[MSSQL Farm 백업 {0}] DB={1} Type={2} · 성공 {3} / 실패 {4} / 건너뜀 {5}" -f `
                $status, $Database, $Type, $ok.Count, $failed.Count, $skipped.Count
    if ($failed.Count -gt 0) { $summary += ("  실패: {0}" -f (($failed.Instance) -join ', ')) }
    Send-BackupNotification -Url $NotifyWebhook -Message $summary
}

if ($skipped.Count -gt 0) {
    Write-Host ("건너뜀 {0}건: {1}" -f $skipped.Count, (($skipped.Instance) -join ', ')) -ForegroundColor Yellow
}
if ($failed.Count -gt 0) {
    Write-Host ("실패 {0}건: {1}" -f $failed.Count, (($failed.Instance) -join ', ')) -ForegroundColor Red
    exit 1   # 스케줄러가 실패를 감지할 수 있도록 0 이 아닌 코드로 종료
}
Write-Host ("성공 {0}건{1}." -f $ok.Count, $(if ($skipped.Count) { " (건너뜀 $($skipped.Count)건)" } else { '' })) -ForegroundColor Green
