#Requires -Version 5.1
# ═══════════════════════════════════════════════════════════════════════════
#  _common.ps1  —  모든 관리 스크립트가 함께 쓰는 "공용 함수 모음"
# ═══════════════════════════════════════════════════════════════════════════
#
#  [이 파일은 직접 실행하지 않습니다]
#  start.ps1 / stop.ps1 / backup.ps1 같은 스크립트들이 맨 위에서
#  이 파일을 "불러와서(dot-source)" 안에 정의된 함수들을 가져다 씁니다.
#
#      . "$PSScriptRoot\lib\_common.ps1"
#      ↑ 맨 앞의 점(.)이 "이 파일의 내용을 지금 스크립트 안으로 그대로 붙여넣기"
#        라는 뜻입니다. 그래서 아래 함수들을 자기 것처럼 호출할 수 있습니다.
#
#  [핵심 원칙]
#  · 설정값은 전부 compose/.env 한 곳에만 있습니다. 스크립트에는 값을 적지 않습니다.
#  · 인스턴스(=SQL Server 컨테이너) 목록도 .env 를 훑어서 자동으로 알아냅니다.
#    → 새 인스턴스를 추가할 때 스크립트는 손댈 필요가 없습니다.
#
#  [폴더 구조 — 이 파일 위치로 저장소 최상위 폴더를 거꾸로 계산합니다]
#      <저장소 루트>\
#        ├─ scripts\lib\_common.ps1   ← 지금 이 파일
#        └─ compose\
#             ├─ compose.yml          ← 컨테이너 "구조"만 정의
#             └─ .env                 ← 모든 "설정값"이 있는 유일한 파일
# ═══════════════════════════════════════════════════════════════════════════


# ───────────────────────────────────────────────────────────────────────────
#  중요한 경로들을 미리 계산해 둡니다.
#
#  $PSScriptRoot 는 "지금 이 파일이 들어 있는 폴더"를 뜻하는 자동 변수입니다.
#  이 파일은 ...\scripts\lib\ 안에 있으므로,
#    · 한 단계 위로 올라가면  ...\scripts
#    · 두 단계 위로 올라가면  ...\ (저장소 루트)
#  Split-Path -Parent 는 "경로에서 마지막 폴더를 떼어내 상위 폴더를 얻기"입니다.
# ───────────────────────────────────────────────────────────────────────────
$script:RepoRoot    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ComposeDir  = Join-Path $script:RepoRoot 'compose'          # compose 폴더
$script:ComposeFile = Join-Path $script:ComposeDir 'compose.yml'    # 구조 정의 파일
$script:EnvFile     = Join-Path $script:ComposeDir '.env'           # 설정값 파일

# ($script: 는 "이 스크립트 실행 동안만 기억해 두는 값"이라는 뜻입니다.)


# ───────────────────────────────────────────────────────────────────────────
#  Read-DotEnv : .env 파일을 읽어 "키=값" 표(사전)로 만들어 돌려줍니다.
#
#  예) .env 안의  DB2019C_PORT=40200  한 줄은
#      결과 표에서  ['DB2019C_PORT'] = '40200'  으로 조회할 수 있게 됩니다.
#
#  한 번 읽은 내용은 $script:DotEnvCache 에 저장해 두고(캐시),
#  다음에 또 부르면 파일을 다시 읽지 않고 저장해 둔 것을 그대로 돌려줍니다.
# ───────────────────────────────────────────────────────────────────────────
$script:DotEnvCache = $null   # 아직 안 읽은 상태를 뜻하는 빈 값

function Read-DotEnv {
    [CmdletBinding()]
    param(
        # 기본값은 compose\.env. 필요하면 다른 경로를 줄 수도 있습니다.
        [string]$Path = $script:EnvFile
    )

    # 이미 한 번 읽어 뒀다면 그걸 그대로 돌려주고 끝냅니다. (속도 향상)
    if ($script:DotEnvCache) { return $script:DotEnvCache }

    if (-not (Test-Path $Path)) {
        throw ".env 파일을 찾을 수 없습니다: $Path"
    }

    # [ordered]@{} 는 "넣은 순서를 기억하는 사전(딕셔너리)"입니다.
    $map = [ordered]@{}

    foreach ($line in (Get-Content -Path $Path -Encoding UTF8)) {
        $trimmed = $line.Trim()   # 줄 앞뒤 공백 제거

        # 빈 줄이거나 '#' 으로 시작하는 주석 줄은 건너뜁니다.
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

        # '=' 위치를 찾아 왼쪽(키)과 오른쪽(값)으로 나눕니다.
        $eq = $trimmed.IndexOf('=')
        if ($eq -lt 1) { continue }   # '=' 이 없거나 맨 앞이면 잘못된 줄 → 건너뜀

        $key   = $trimmed.Substring(0, $eq).Trim()
        $value = $trimmed.Substring($eq + 1).Trim().Trim('"')   # 양옆 큰따옴표도 제거
        $map[$key] = $value
    }

    $script:DotEnvCache = $map   # 다음 호출을 위해 저장
    return $map
}


# ───────────────────────────────────────────────────────────────────────────
#  Set-DotEnvValue : .env 의 한 키 값을 파일에서 직접 고쳐 씁니다.
#
#  Read-DotEnv 가 주는 "파싱된 사전"은 주석·순서를 잃으므로, 값 하나만 바꿀 때는
#  원문 줄을 그대로 두고 해당 키 줄만 교체합니다(주석/다른 값 보존).
#    · 키가 있으면 그 줄을 "<Key>=<Value>" 로 교체
#    · 없으면 파일 끝에 "<Key>=<Value>" 를 추가
#  compose 가 읽는 파일이라 BOM 없이(UTF8Encoding $false) 저장하고, 값 캐시를 비웁니다.
#  주의: 값은 원문 그대로 씁니다($$ 이스케이프/따옴표를 넣지 않음). 스크립트가 .env
#        원문을 그대로 쓰는 값(비밀번호 등)에 맞춘 것입니다.
#  돌려주는 값: 기존 키를 교체했으면 $true, 새로 추가했으면 $false.
# ───────────────────────────────────────────────────────────────────────────
function Set-DotEnvValue {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value,
        [string]$Path = $script:EnvFile
    )

    if (-not (Test-Path $Path)) { throw ".env 파일을 찾을 수 없습니다: $Path" }

    $lines    = @(Get-Content -Path $Path -Encoding UTF8)
    $replaced = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $eq = $trimmed.IndexOf('=')
        if ($eq -lt 1) { continue }
        if ($trimmed.Substring(0, $eq).Trim() -eq $Key) {
            $lines[$i] = "$Key=$Value"
            $replaced  = $true
            break
        }
    }
    if (-not $replaced) { $lines += "$Key=$Value" }

    # BOM 없는 UTF-8 로 기록 (compose/.env 는 BOM 없어야 함)
    [System.IO.File]::WriteAllLines($Path, $lines, (New-Object System.Text.UTF8Encoding($false)))

    # 파일이 바뀌었으니 다음 Read-DotEnv 가 새로 읽도록 캐시를 비웁니다.
    $script:DotEnvCache = $null
    return $replaced
}


# ───────────────────────────────────────────────────────────────────────────
#  Assert-Docker : Docker 가 켜져 있는지 확인합니다.
#  Docker Desktop 이 꺼져 있으면 이후 모든 명령이 실패하므로, 먼저 점검합니다.
# ───────────────────────────────────────────────────────────────────────────
function Assert-Docker {
    docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
    # $LASTEXITCODE : 바로 앞 외부 명령의 종료 코드. 0 이 아니면 실패한 것입니다.
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker 데몬에 연결할 수 없습니다. Docker Desktop 이 실행 중인지 확인하세요.'
    }
}


# ───────────────────────────────────────────────────────────────────────────
#  Get-Instances : .env 를 훑어 "관리 대상 인스턴스 목록"을 만들어 돌려줍니다.
#
#  규약: 한 인스턴스는 .env 에서 접두사(PREFIX)가 같은 3줄로 표현됩니다.
#        DB2019C_NAME=Db2019C          ← 컨테이너 이름
#        DB2019C_PORT=40200            ← 호스트에서 접속할 포트
#        DB2019C_DIR=Db2019C2019       ← 데이터가 저장되는 폴더 이름
#
#  이 함수는 '*_PORT' 로 끝나는 키를 모두 찾아 인스턴스로 인식합니다.
#  (단, 모든 컨테이너 내부 공통 포트인 MSSQL_PORT 는 인스턴스가 아니므로 제외)
# ───────────────────────────────────────────────────────────────────────────
function Get-Instances {
    $config = Read-DotEnv
    $root   = $config['DATA_ROOT']   # 데이터가 실제로 저장되는 최상위 폴더 (예: C:/docker)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw '.env 에 DATA_ROOT 가 없습니다.'
    }

    # '*_PORT' 로 끝나는 키만 골라 하나씩 인스턴스 객체로 변환합니다.
    $config.Keys |
        Where-Object { $_ -like '*_PORT' -and $_ -ne 'MSSQL_PORT' } |
        ForEach-Object {
            $prefix = $_ -replace '_PORT$', ''   # 'DB2019C_PORT' → 'DB2019C'

            # 이름이 없으면 접두사를 그대로 이름으로 씁니다. (보통은 _NAME 이 있습니다)
            $name = $config["${prefix}_NAME"]
            if (-not $name) { $name = $prefix }

            # 데이터 폴더 전체 경로 = DATA_ROOT \ <XXX_DIR> \ data
            $dataDir = Join-Path $root (Join-Path $config["${prefix}_DIR"] 'data')

            # [pscustomobject] : 여러 값을 이름표를 붙여 한 덩어리로 묶는 방법.
            [pscustomobject]@{
                Service = $prefix.ToLower()      # compose.yml 의 서비스 키 (= 접두사 소문자)
                Name    = $name                  # 컨테이너 이름 (container_name)
                Port    = [int]$config[$_]        # 호스트 포트 (숫자로 변환)
                DataDir = $dataDir               # 데이터 폴더 경로
            }
        }
}


# ───────────────────────────────────────────────────────────────────────────
#  Resolve-Services : 사용자가 -Service 로 넘긴 이름이 실제로 있는지 검증합니다.
#
#  오타(예: 'sceince')를 미리 잡아, 엉뚱한 대상에 명령이 나가는 것을 막습니다.
#  · 아무것도 안 넘기면 → 빈 목록을 돌려줍니다(= "전체 대상"이라는 뜻).
#  · 잘못된 이름이 있으면 → 사용 가능한 목록과 함께 오류를 냅니다.
# ───────────────────────────────────────────────────────────────────────────
function Resolve-Services {
    param([string[]]$Service = @())

    if ($Service.Count -eq 0) { return @() }   # 지정 없음 = 전체

    $valid = (Get-Instances).Service           # 실제 존재하는 서비스 이름들
    $bad   = $Service | Where-Object { $_.ToLower() -notin $valid }

    if ($bad) {
        throw ("알 수 없는 서비스: {0}`n사용 가능: {1}" -f ($bad -join ', '), ($valid -join ', '))
    }

    # 전부 소문자로 통일해서 돌려줍니다. (compose 서비스 키가 소문자이므로)
    return @($Service | ForEach-Object { $_.ToLower() })
}


# ───────────────────────────────────────────────────────────────────────────
#  Get-TargetInstances : "이번 명령이 대상으로 삼을 인스턴스 목록"을 돌려줍니다.
#
#  · -Service 를 주지 않으면 → 전체 인스턴스
#  · -Service db2019c,db2022e 처럼 주면 → 그 인스턴스들만
#
#  start / backup / logs 등 여러 스크립트가 똑같이 하던 일을 여기 한 곳에 모았습니다.
#  (같은 코드를 여러 파일에 복사해 두지 않기 위함)
# ───────────────────────────────────────────────────────────────────────────
function Get-TargetInstances {
    param([string[]]$Service = @())

    $targets   = Resolve-Services -Service $Service   # 오타 검증 + 소문자화
    $instances = Get-Instances

    if ($targets.Count -gt 0) {
        # 지정된 서비스만 남기고 걸러냅니다.
        $instances = @($instances | Where-Object { $_.Service -in $targets })
    }

    return @($instances)   # @(...) 로 감싸 "항상 배열"이 되게 합니다(1개여도 배열).
}


# ───────────────────────────────────────────────────────────────────────────
#  Invoke-Compose : 'docker compose ...' 명령을 대신 실행해 주는 함수.
#
#  compose.yml 과 .env 가 compose\ 폴더 안에 있으므로,
#  docker 가 그 위치를 자동으로 찾지 못합니다. 그래서 매번
#    -f <compose.yml 경로>  --env-file <.env 경로>
#  를 명시적으로 붙여서, 어느 폴더에서 실행하든 올바른 파일을 쓰게 합니다.
#
#  사용 예) Invoke-Compose -Arguments @('up', '-d')
#           → 실제로는  docker compose -f ... --env-file ... up -d
# ───────────────────────────────────────────────────────────────────────────
function Invoke-Compose {
    param([Parameter(Mandatory)][string[]]$Arguments)

    # docker compose "전체 옵션"(-f, --env-file)은 하위 명령(up/down/...) 앞에 와야 합니다.
    $baseArgs = @('-f', $script:ComposeFile, '--env-file', $script:EnvFile)

    # 사용자에게는 핵심 부분(up -d 등)만 보여 주어 화면을 깔끔하게 유지합니다.
    Write-Host ("  > docker compose {0}" -f ($Arguments -join ' ')) -ForegroundColor DarkGray

    # @baseArgs @Arguments : 두 배열을 순서대로 펼쳐서 docker 에 전달합니다.
    & docker compose @baseArgs @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw ("docker compose {0} 실패 (종료 코드 {1})" -f $Arguments[0], $LASTEXITCODE)
    }
}


# ═══════════════════════════════════════════════════════════════════════════
#  farm 상태 수집 도우미  (status.ps1 · report.ps1 이 함께 씁니다)
#
#  두 스크립트가 만드는 상태 표의 "TCP"(포트 응답)·"Data"(용량) 칸을 채우는
#  헬퍼입니다. 예전엔 각 스크립트 안에 같은 함수를 복제해 두어 한쪽만 고치면
#  어긋날 위험이 있었습니다. 여기 한 곳으로 올려 두 스크립트가 공유합니다.
# ═══════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────
#  Test-TcpPort : 특정 포트로 TCP 접속이 되는지 참/거짓으로 확인합니다.
#  (SQL Server 가 실제로 연결을 받아 주는지 보는 간단한 점검입니다.)
# ───────────────────────────────────────────────────────────────────────────
function Test-TcpPort {
    param(
        [int]$Port,
        [int]$TimeoutMs = 700   # 이 시간 안에 응답이 없으면 실패로 간주
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        # 비동기로 접속을 시도하고, 정해진 시간만큼만 기다립니다.
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()   # 성공하든 실패하든 연결은 항상 닫습니다.
    }
}


# ───────────────────────────────────────────────────────────────────────────
#  Get-DirSizeMB : 폴더 안 모든 파일 용량을 합쳐 MB 단위로 돌려줍니다.
#  폴더가 없으면 $null 을, 비어 있으면 0 을 돌려줍니다.
# ───────────────────────────────────────────────────────────────────────────
function Get-DirSizeMB {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }

    try {
        $sum = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
        if (-not $sum) { return 0 }
        return [math]::Round($sum / 1MB, 1)   # 바이트 → MB, 소수점 첫째 자리까지
    } catch {
        return $null
    }
}


# ═══════════════════════════════════════════════════════════════════════════
#  SQL 실행 관련 도우미들
#  (백업 스크립트 등에서 컨테이너 안의 SQL Server 에 명령을 보낼 때 씁니다)
# ═══════════════════════════════════════════════════════════════════════════

# 컨테이너마다 찾은 sqlcmd 경로를 기억해 두는 캐시입니다.
$script:SqlcmdCache = @{}

# ───────────────────────────────────────────────────────────────────────────
#  Get-SqlcmdInvocation : 컨테이너 안에서 쓸 수 있는 sqlcmd 실행 경로를 찾습니다.
#
#  SQL Server 버전마다 sqlcmd 위치가 다릅니다.
#    · 2019 : /opt/mssql-tools/bin/sqlcmd
#    · 2022 : /opt/mssql-tools18/bin/sqlcmd -C   (-C 는 인증서 신뢰 옵션)
#  .env 에 두 후보 경로가 있고, 이 함수는 컨테이너 안에서 실제로 어느 것이
#  존재하는지(test -x) 확인해 맞는 것을 골라 줍니다. 즉 버전을 자동 판별합니다.
# ───────────────────────────────────────────────────────────────────────────
function Get-SqlcmdInvocation {
    param([Parameter(Mandatory)][string]$Container)

    # 이미 이 컨테이너에 대해 찾아 뒀다면 그대로 돌려줍니다.
    if ($script:SqlcmdCache.ContainsKey($Container)) {
        return $script:SqlcmdCache[$Container]
    }

    $config = Read-DotEnv

    # 2022 후보를 먼저 확인하고, 없으면 2019 후보를 확인합니다.
    foreach ($candidate in @($config['MSSQL_2022_SQLCMD'], $config['MSSQL_2019_SQLCMD'])) {
        if (-not $candidate) { continue }

        # 예: '/opt/mssql-tools18/bin/sqlcmd -C' → ['/opt/.../sqlcmd', '-C']
        $parts = $candidate -split '\s+'

        # 컨테이너 안에서 그 파일이 "실행 가능한 파일"로 존재하는지 검사합니다.
        docker exec $Container test -x $parts[0] 2>$null
        if ($LASTEXITCODE -eq 0) {
            $script:SqlcmdCache[$Container] = $parts   # 찾았으면 기억
            return $parts
        }
    }

    throw "$Container 안에서 sqlcmd 를 찾지 못했습니다. .env 의 MSSQL_*_SQLCMD 경로를 확인하세요."
}


# ───────────────────────────────────────────────────────────────────────────
#  Test-ContainerRunning : 컨테이너가 지금 "실행 중"인지 참/거짓으로 알려줍니다.
# ───────────────────────────────────────────────────────────────────────────
function Test-ContainerRunning {
    param([Parameter(Mandatory)][string]$Container)

    $state = docker inspect --format '{{.State.Running}}' $Container 2>$null
    return ($LASTEXITCODE -eq 0 -and $state -eq 'true')
}


# ───────────────────────────────────────────────────────────────────────────
#  Get-ContainerHealth : 컨테이너 하나의 헬스체크 상태를 표준 토큰으로 돌려줍니다.
#
#  status.ps1 의 상태 표와 Wait-Healthy 가 함께 씁니다(헬스 판정 로직을 한 곳에).
#  docker inspect 의 .State.Health.Status 를 직접 읽으므로, 사람이 읽는
#  docker ps 의 "Up ... (healthy)" 문자열 형식에 의존하지 않습니다.
#
#  돌려주는 값(모두 소문자):
#    · 'healthy'   : 헬스체크 통과
#    · 'unhealthy' : 헬스체크 실패
#    · 'starting'  : 헬스체크 진행 중 (아직 판정 전)
#    · 'none'      : 헬스체크가 정의돼 있지 않음
#    · 'missing'   : 그런 이름의 컨테이너가 없음
# ───────────────────────────────────────────────────────────────────────────
function Get-ContainerHealth {
    param([Parameter(Mandatory)][string]$Container)

    # {{if .State.Health}} : 헬스체크가 정의된 컨테이너만 .Status 값이 있습니다.
    #                        없으면 'none' 을 찍게 하여 "헬스체크 없음"과 구분합니다.
    $format = '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
    $status = docker inspect --format $format $Container 2>$null

    # 컨테이너 자체가 없으면 inspect 가 실패합니다(종료 코드 ≠ 0).
    if ($LASTEXITCODE -ne 0) { return 'missing' }

    $status = "$status".Trim()
    if ([string]::IsNullOrEmpty($status)) { return 'none' }
    return $status
}


# ───────────────────────────────────────────────────────────────────────────
#  Wait-Healthy : 대상 인스턴스가 모두 "정상"이 될 때까지 기다립니다(타임아웃 포함).
#
#  스케줄러·CI·연쇄 스크립트에서 "기동이 실제로 끝났는지"를 알 수 있게 해 줍니다.
#  임의의 Start-Sleep 로 짐작하는 대신 각 컨테이너의 헬스 상태를 폴링합니다.
#
#  "정상"의 정의:
#    · 헬스체크가 있는 컨테이너 → 'healthy'
#    · 헬스체크가 없는 컨테이너 → 실행 중(running)이면 통과 (판정할 헬스가 없으므로)
#
#  돌려주는 값: 전부 정상이 되면 $true, 타임아웃되면 $false.
#  (호출부에서 $false 면 exit 1 로 실패를 알릴 수 있습니다.)
# ───────────────────────────────────────────────────────────────────────────
function Wait-Healthy {
    param(
        [Parameter(Mandatory)][object[]]$Instances,   # Get-TargetInstances 결과(.Name 사용)
        [int]$TimeoutSec = 120,                        # 이 시간(초)을 넘기면 대기를 포기
        [int]$PollSec = 3                              # 폴링 간격(초)
    )

    if (@($Instances).Count -eq 0) { return $true }    # 대상이 없으면 기다릴 것도 없음

    # 종료 시각을 미리 정해 두고, 이 시각을 넘기면 포기합니다.
    $deadline = (Get-Date).AddSeconds($TimeoutSec)

    # 아직 정상이 아닌 컨테이너 이름들. 매 회차 정상이 된 것은 여기서 빠집니다.
    $pending = [System.Collections.Generic.List[string]]::new()
    foreach ($instance in $Instances) { $pending.Add($instance.Name) }

    while ($true) {
        # 이번 회차에도 아직 정상이 아닌 것만 다음 회차로 넘깁니다.
        $stillPending = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $pending) {
            $health = Get-ContainerHealth -Container $name

            $done =
                if     ($health -eq 'healthy') { $true }
                elseif ($health -eq 'none')    { Test-ContainerRunning -Container $name }  # 헬스체크 없음 → 실행 중이면 통과
                else                           { $false }                                   # starting/unhealthy/missing → 계속 대기

            if (-not $done) { $stillPending.Add($name) }
        }
        $pending = $stillPending

        if ($pending.Count -eq 0) {
            Write-Host '  모두 healthy.' -ForegroundColor Green
            return $true
        }

        # 시간이 다 됐으면 아직 안 된 것을 보여 주고 실패로 끝냅니다.
        if ((Get-Date) -ge $deadline) {
            Write-Host ("  타임아웃({0}초): {1} 아직 healthy 아님" -f $TimeoutSec, ($pending -join ', ')) -ForegroundColor Red
            return $false
        }

        Write-Host ("  대기 중... 남음: {0}" -f ($pending -join ', ')) -ForegroundColor DarkGray
        Start-Sleep -Seconds $PollSec
    }
}


# ───────────────────────────────────────────────────────────────────────────
#  Invoke-Sql : 컨테이너 안의 SQL Server 에 T-SQL 한 문장을 실행합니다.
#
#  비밀번호를 명령줄에 직접 쓰면 특수문자(!, $ 등) 때문에 셸에서 문제가 생길 수
#  있어, SQLCMDPASSWORD 라는 환경변수로 안전하게 전달합니다.
#
#  돌려주는 값: 성공 여부(Success)와 출력 텍스트(Output)를 묶은 객체.
# ───────────────────────────────────────────────────────────────────────────
function Invoke-Sql {
    param(
        [Parameter(Mandatory)][string]$Container,   # 대상 컨테이너 이름
        [Parameter(Mandatory)][string]$Query,       # 실행할 T-SQL 문장
        [string]$Database = 'master',               # 접속할 DB (기본: master)
        [int]$LoginTimeout = 10,                     # 로그인 대기 시간(초)
        [string]$Separator,                          # 값을 주면 컬럼을 이 문자로 구분(-s). 여러 컬럼 결과 파싱용.
        [string]$Password                            # 값을 주면 .env 대신 이 비밀번호로 접속 (비밀번호 회전/롤백용)
    )

    # 기본은 .env 의 SA 비밀번호. -Password 를 주면 그 값으로 접속합니다.
    $pw     = if ($Password) { $Password } else { (Read-DotEnv)['MSSQL_SA_PASSWORD'] }
    $sqlcmd = Get-SqlcmdInvocation -Container $Container

    # docker exec 에 넘길 인자들을 순서대로 조립합니다.
    #  -e SQLCMDPASSWORD=... : 컨테이너 안에서 비밀번호를 환경변수로 받게 함
    #  -S localhost -U sa    : 자기 자신에게 sa 계정으로 접속
    #  -b : 오류가 나면 종료 코드를 0 이 아니게 (실패를 감지하려고)
    #  -h -1 / -W : 머리글 없이, 여분 공백 없이 깔끔하게 출력
    #  -s "<구분자>" : (선택) 컬럼 사이에 이 문자를 넣어, 여러 컬럼을 나눠 읽기 쉽게 함
    #  -Q : 이 쿼리를 실행하고 종료
    #  ※ -Q 는 반드시 맨 뒤여야 하므로, -s 는 그 앞쪽에 끼워 넣습니다.
    $sqlArgs = @('-S', 'localhost', '-U', 'sa', '-d', $Database,
                 '-l', "$LoginTimeout", '-b', '-h', '-1', '-W')
    if ($Separator) { $sqlArgs += @('-s', $Separator) }
    $sqlArgs += @('-Q', $Query)

    $dockerArgs = @('exec', '-e', "SQLCMDPASSWORD=$pw", $Container) +
                  $sqlcmd + $sqlArgs

    # 2>&1 : 오류 출력도 일반 출력과 함께 받아, 실패 원인을 확인할 수 있게 합니다.
    $output = & docker @dockerArgs 2>&1

    return [pscustomobject]@{
        Success = ($LASTEXITCODE -eq 0)
        Output  = ($output -join "`n").Trim()
    }
}


# ═══════════════════════════════════════════════════════════════════════════
#  알림 (webhook)
#  (백업/복원 등 배치 작업의 결과 요약을 무인 운영자에게 능동적으로 알릴 때 씁니다)
# ═══════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────
#  Send-WebhookNotification : 작업 요약을 webhook 으로 보냅니다.
#
#  backup.ps1 · restore.ps1 이 함께 씁니다(원래 backup.ps1 안에만 있던 것을
#  공용으로 올려 두 스크립트가 같은 전송 로직을 공유합니다).
#  Teams·Slack 인커밍 webhook 모두 {"text": "..."} 페이로드를 받으므로,
#  하나의 함수로 양쪽에 보낼 수 있습니다. 본문은 한글이 깨지지 않도록
#  UTF-8 바이트로 인코딩해 전송합니다.
#
#  ※ 알림 전송 실패가 작업 결과(종료 코드)를 바꾸면 안 되므로, 실패해도
#     throw 하지 않고 경고만 남깁니다(호출부의 exit 1 판정에 영향 없음).
# ───────────────────────────────────────────────────────────────────────────
function Send-WebhookNotification {
    param(
        [Parameter(Mandatory)][string]$Url,       # 보낼 대상 webhook 주소
        [Parameter(Mandatory)][string]$Message    # 보낼 요약 문자열
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
