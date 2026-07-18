#Requires -Version 5.1
<#
    _common.ps1 의 자동 발견/파싱 로직 단위 테스트 (Pester 5+).

    실행:  .\scripts\test.ps1        (또는)  .\scripts\check.ps1 -Test

    검증 대상:
      · Read-DotEnv     — .env 파싱 규칙 (주석/따옴표/$$/인라인 주석/공백)
      · Get-Instances   — _PORT 스캔으로 인스턴스 발견 (MSSQL_PORT 제외)
      · Resolve-Services — -Service 오타 검증 및 소문자 정규화

    [주입 방식] _common.ps1 은 설정을 $script:DotEnvCache 에 캐시합니다. 테스트는
    이 캐시에 직접 사전(dictionary)을 넣어, 파일 없이 원하는 .env 상태를 흉내 냅니다.
    Read-DotEnv 파싱 자체를 볼 때만 임시 파일($TestDrive)을 씁니다.
#>

BeforeAll {
    # 테스트 대상 라이브러리를 현재 스코프로 불러옵니다.
    . "$PSScriptRoot\..\scripts\lib\_common.ps1"
}


Describe 'Read-DotEnv' {

    BeforeAll {
        # 파싱 규칙을 골고루 건드리는 견본 .env 를 임시 폴더에 만듭니다.
        $fixture = Join-Path $TestDrive 'sample.env'
        @'
# 전체 주석 줄 — 무시되어야 함
DATA_ROOT=C:/docker

DB2019C_NAME=Db2019C
QUOTED="hello world"
PW=Pa$$w0rd!
INLINE=value  # 인라인 주석은 값에 남습니다
=badline
NOEQUALS
   SPACED_KEY   =   spaced value
'@ | Set-Content -Path $fixture -Encoding UTF8
    }

    BeforeEach {
        $script:DotEnvCache = $null   # 캐시를 비워 매 테스트가 파일을 새로 읽게 합니다.
    }

    It '일반 키=값을 읽는다' {
        $env = Read-DotEnv -Path $fixture
        $env['DATA_ROOT'] | Should -Be 'C:/docker'
    }

    It '전체 주석 줄과 빈 줄, = 없는 줄은 건너뛴다' {
        $env = Read-DotEnv -Path $fixture
        $env.Contains('') | Should -BeFalse          # '=badline' → = 이 맨 앞이라 무시
        $env.Contains('NOEQUALS') | Should -BeFalse   # '=' 이 없는 줄 무시
    }

    It '값 양옆의 큰따옴표를 제거한다' {
        $env = Read-DotEnv -Path $fixture
        $env['QUOTED'] | Should -Be 'hello world'
    }

    It '$$ 를 문자 그대로 읽는다 (변형하지 않음)' {
        $env = Read-DotEnv -Path $fixture
        $env['PW'] | Should -Be 'Pa$$w0rd!'
    }

    It '값 뒤 인라인 주석은 값의 일부로 남는다 (그래서 규약이 금지함)' {
        # 이 특성(characterization) 때문에 .env 는 값 옆 인라인 주석을 금지합니다.
        # doctor.ps1 이 이 형식을 오류로 잡는 이유이기도 합니다.
        $env = Read-DotEnv -Path $fixture
        $env['INLINE'] | Should -Match '#'
    }

    It '키와 값 양옆 공백을 제거한다' {
        $env = Read-DotEnv -Path $fixture
        $env['SPACED_KEY'] | Should -Be 'spaced value'
    }

    It '두 번째 호출은 캐시를 돌려준다 (경로 없이도 같은 결과)' {
        $a = Read-DotEnv -Path $fixture
        $b = Read-DotEnv                                  # 경로 없이 호출 → 캐시 반환
        $b['DATA_ROOT'] | Should -Be 'C:/docker'
        [object]::ReferenceEquals($a, $b) | Should -BeTrue
    }
}


Describe 'Get-Instances' {

    BeforeEach {
        # 파일 대신 캐시에 직접 상태를 주입합니다.
        $script:DotEnvCache = [ordered]@{
            DATA_ROOT    = 'C:/docker'
            MSSQL_PORT   = '1433'          # 내부 공통 포트 → 인스턴스가 아님
            DB2019C_NAME = 'Db2019C'
            DB2019C_PORT = '40200'
            DB2019C_DIR  = 'Db2019C'
            DB2022A_PORT = '41000'         # _NAME 일부러 생략 → 접두사를 이름으로 쓰는지 확인
            DB2022A_DIR  = 'Db2022A'
        }
    }

    It '_PORT 키로 인스턴스를 발견하고 MSSQL_PORT 는 제외한다' {
        $inst = Get-Instances
        @($inst).Count | Should -Be 2
        @($inst | Where-Object { $_.Service -eq 'mssql' }).Count | Should -Be 0
    }

    It 'Service/Name/Port/DataDir 를 올바르게 채운다' {
        $db = Get-Instances | Where-Object { $_.Service -eq 'db2019c' }
        $db.Name    | Should -Be 'Db2019C'
        $db.Port    | Should -Be 40200
        $db.Port    | Should -BeOfType [int]
        $db.DataDir | Should -Match 'Db2019C'
        $db.DataDir | Should -Match 'data$'
    }

    It '_NAME 이 없으면 접두사를 이름으로 쓴다' {
        $db = Get-Instances | Where-Object { $_.Service -eq 'db2022a' }
        $db.Name | Should -Be 'DB2022A'
    }

    It 'DATA_ROOT 가 없으면 throw 한다' {
        $script:DotEnvCache = [ordered]@{ DB2019C_PORT = '40200' }
        { Get-Instances } | Should -Throw
    }
}


Describe 'Resolve-Services' {

    BeforeEach {
        $script:DotEnvCache = [ordered]@{
            DATA_ROOT    = 'C:/docker'
            DB2019C_PORT = '40200'
            DB2019C_DIR  = 'Db2019C'
            DB2022A_PORT = '41000'
            DB2022A_DIR  = 'Db2022A'
        }
    }

    It '빈 입력은 빈 배열(=전체)을 돌려준다' {
        @(Resolve-Services -Service @()).Count | Should -Be 0
    }

    It '유효한 서비스를 소문자로 정규화해 돌려준다' {
        Resolve-Services -Service 'db2019c' | Should -Be @('db2019c')
    }

    It '대소문자를 무시하고 매칭한다' {
        Resolve-Services -Service 'DB2019C' | Should -Be @('db2019c')
    }

    It '오타는 사용 가능 목록과 함께 throw 한다' {
        { Resolve-Services -Service 'db9999' } | Should -Throw -ExpectedMessage '*db2019c*'
    }
}


Describe 'Set-DotEnvValue' {

    BeforeEach {
        $script:DotEnvCache = $null   # 매 테스트가 파일을 새로 읽도록 캐시를 비웁니다.
        $fixture = Join-Path $TestDrive 'rw.env'
        @'
# 주석 줄 — 보존되어야 함
DATA_ROOT=C:/docker
MSSQL_SA_PASSWORD=OldPass1!
DB2019C_PORT=40200
'@ | Set-Content -Path $fixture -Encoding UTF8
    }

    It '기존 키 값을 교체하고($true 반환) 다른 줄은 보존한다' {
        Set-DotEnvValue -Key 'MSSQL_SA_PASSWORD' -Value 'NewPass2@' -Path $fixture | Should -BeTrue
        $lines = Get-Content -Path $fixture -Encoding UTF8
        @($lines | Where-Object { $_ -eq 'MSSQL_SA_PASSWORD=NewPass2@' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -eq '# 주석 줄 — 보존되어야 함' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -eq 'DB2019C_PORT=40200' }).Count | Should -Be 1
    }

    It '없는 키는 파일 끝에 추가한다($false 반환)' {
        Set-DotEnvValue -Key 'NEW_KEY' -Value 'v1' -Path $fixture | Should -BeFalse
        (Get-Content -Path $fixture -Encoding UTF8)[-1] | Should -Be 'NEW_KEY=v1'
    }

    It '교체 후 Read-DotEnv 가 새 값을 돌려준다 (캐시 무효화)' {
        Read-DotEnv -Path $fixture | Out-Null                 # 캐시를 먼저 채움
        Set-DotEnvValue -Key 'DATA_ROOT' -Value 'E:/x' -Path $fixture | Out-Null
        (Read-DotEnv -Path $fixture)['DATA_ROOT'] | Should -Be 'E:/x'
    }
}


Describe 'Get-DirSizeMB' {

    It '없는 폴더에는 $null 을 돌려준다' {
        Get-DirSizeMB -Path (Join-Path $TestDrive 'nope') | Should -Be $null
    }

    It '빈 폴더에는 0 을 돌려준다' {
        $dir = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Get-DirSizeMB -Path $dir | Should -Be 0
    }

    It '하위 폴더까지 합산하고 MB(소수 첫째)로 반올림한다' {
        # 최상위 1 MB + 하위 폴더 0.5 MB = 1.5 MB 인지 확인(재귀 + 반올림).
        $dir = Join-Path $TestDrive 'sized'
        $sub = Join-Path $dir 'sub'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $dir 'a.bin'), [byte[]]::new(1048576))  # 1 MB
        [System.IO.File]::WriteAllBytes((Join-Path $sub 'b.bin'), [byte[]]::new(524288))   # 0.5 MB
        Get-DirSizeMB -Path $dir | Should -Be 1.5
    }
}


Describe 'Test-TcpPort' {

    It '열려 있는 포트에는 $true 를 돌려준다' {
        # 루프백에 리스너를 띄우고(포트는 OS 가 배정) 그 포트로 접속을 확인합니다.
        $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        try {
            $port = $listener.LocalEndpoint.Port
            Test-TcpPort -Port $port | Should -BeTrue
        } finally {
            $listener.Stop()
        }
    }

    It '닫혀 있는 포트에는 $false 를 돌려준다' {
        # 리스너로 빈 포트 번호만 잠깐 확보한 뒤 즉시 닫아, 아무도 안 듣는 포트를 만듭니다.
        $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
        $listener.Stop()
        Test-TcpPort -Port $port -TimeoutMs 300 | Should -BeFalse
    }
}
