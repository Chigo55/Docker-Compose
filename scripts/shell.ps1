#Requires -Version 5.1
<#
.SYNOPSIS
    지정한 인스턴스에 대화형 sqlcmd 세션을 바로 엽니다.

.DESCRIPTION
    임시 확인·수정을 하려고 매번 긴
        docker exec -it <컨테이너> /opt/mssql-tools.../sqlcmd -S localhost -U sa -P ...
    를 치는 수고를 없앱니다. 서비스 키 하나만 주면 해당 인스턴스에 sqlcmd 프롬프트(1>)를
    바로 띄웁니다. 나머지는 _common.ps1 의 헬퍼로 자동 처리합니다.

      · 버전 자동 판별 : Get-SqlcmdInvocation 이 2019/2022 sqlcmd 경로를 컨테이너에서
                         실제 확인(test -x)해 맞는 것을 고릅니다(2022 는 -C 포함).
      · 비밀번호 자동 주입 : .env 의 MSSQL_SA_PASSWORD 를 SQLCMDPASSWORD 환경변수로 넘겨
                         명령줄 인용 문제 없이 접속합니다(-P 를 쓰지 않음, Invoke-Sql 과 동일).
      · 대화형(-it)    : docker exec -it 로 붙어 진짜 sqlcmd 세션을 씁니다.

    대화형 세션이라 대상은 "정확히 하나"여야 합니다. -Service 를 비우면(=전체) 여러
    인스턴스가 잡히므로, 인스턴스가 2개 이상일 때는 -Service 로 하나를 지정해야 합니다.

    세션을 끝내려면 sqlcmd 프롬프트에서 EXIT 또는 QUIT 을 입력합니다(또는 Ctrl+C).

.EXAMPLE
    .\scripts\shell.ps1 -Service db2019c
    db2019c 인스턴스에 master DB 로 대화형 sqlcmd 세션을 엽니다.

.EXAMPLE
    .\scripts\shell.ps1 db2022b -Database MyDb
    db2022b 인스턴스에 MyDb 를 기본 DB 로 접속합니다(서비스 키는 첫 인자로도 받습니다).
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Service = @(),      # 대상 인스턴스(정확히 하나). 첫 인자로도 받습니다.
    [string]$Database = 'master',  # 접속할 기본 DB (기본: master)
    [int]$LoginTimeout = 10        # 로그인 대기 시간(초)
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\_common.ps1"
Set-Location -Path $RepoRoot

Assert-Docker

# ── 대상 인스턴스 결정: 대화형이라 정확히 하나여야 합니다. ────────────────────
#    Get-TargetInstances 가 -Service 오타를 먼저 검증(Resolve-Services)합니다.
#    · -Service 없음 → 전체가 잡혀 개수가 2 이상이면 여기서 막습니다.
#    · -Service 2개 이상 → 마찬가지로 막습니다.
$instances = Get-TargetInstances -Service $Service
if (@($instances).Count -ne 1) {
    throw ("대화형 세션은 인스턴스를 정확히 하나 지정해야 합니다(-Service). 현재 대상 {0}개.`n사용 가능: {1}" -f `
        @($instances).Count, ((Get-Instances).Service -join ', '))
}
$instance = $instances[0]

# ── 컨테이너가 실행 중이어야 붙을 수 있습니다. ────────────────────────────────
if (-not (Test-ContainerRunning -Container $instance.Name)) {
    throw ("{0} 컨테이너가 실행 중이 아닙니다. 먼저 .\scripts\start.ps1 -Service {1} 로 기동하세요." -f `
        $instance.Name, $instance.Service)
}

# ── 버전 자동 판별 + 비밀번호 준비 ────────────────────────────────────────────
$sqlcmd = Get-SqlcmdInvocation -Container $instance.Name   # 예: @('/opt/mssql-tools18/bin/sqlcmd', '-C')
$pw     = (Read-DotEnv)['MSSQL_SA_PASSWORD']

Write-Host "`n=== 대화형 sqlcmd 세션 ===" -ForegroundColor Cyan
Write-Host ("  인스턴스 : {0} ({1})" -f $instance.Name, $instance.Service)
Write-Host ("  DB       : {0}" -f $Database)
Write-Host '  종료     : sqlcmd 프롬프트에서 EXIT 또는 QUIT 입력 (또는 Ctrl+C)' -ForegroundColor DarkGray

# ── docker exec -it 로 대화형 sqlcmd 실행 ─────────────────────────────────────
#  -it                    : 대화형 TTY 로 붙습니다(프롬프트 입력을 받기 위함).
#  -e SQLCMDPASSWORD=...   : 비밀번호를 환경변수로 넘겨 -P 인용 문제를 피합니다.
#  -S localhost -U sa      : 컨테이너 자기 자신에 sa 로 접속.
#  -d <DB> -l <timeout>    : 기본 DB, 로그인 대기 시간.
#  ※ -Q(일회성 실행)를 붙이지 않으므로 sqlcmd 프롬프트(1>)로 들어갑니다.
$sqlArgs    = @('-S', 'localhost', '-U', 'sa', '-d', $Database, '-l', "$LoginTimeout")
$dockerArgs = @('exec', '-it', '-e', "SQLCMDPASSWORD=$pw", $instance.Name) + $sqlcmd + $sqlArgs

& docker @dockerArgs
$code = $LASTEXITCODE

Write-Host ("`n세션 종료 (sqlcmd 종료 코드 {0})." -f $code) -ForegroundColor DarkGray
exit $code   # sqlcmd 종료 코드를 그대로 전달 (성공 시 0, 마지막 외부 명령 코드가 새지 않도록 명시)
