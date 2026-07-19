#Requires -Version 5.1
<#
    gen-docs-index.ps1 의 순수 파서 단위 테스트 (Pester 5+).

    실행:  .\scripts\test.ps1        (또는)  .\scripts\check.ps1 -Test

    검증 대상(파일이 아니라 텍스트를 받는 순수 함수):
      · ConvertFrom-DocFrontmatter — '--- ... ---' frontmatter 파싱 + 따옴표 벗기기
      · Get-DocH1                  — 첫 '# 제목' 줄 추출
      · Get-AdrTitle              — 'ADR-NNNN: ' 접두사 제거

    [주입 방식] gen-docs-index.ps1 은 직접 실행할 때만 main 을 돕니다(InvocationName
    가드). 아래처럼 dot-source 하면 함수만 로드되어 파일시스템 없이 테스트할 수 있습니다.
#>

BeforeAll {
    # 테스트 대상 스크립트를 dot-source — 가드 덕분에 main 은 돌지 않고 함수만 들어옵니다.
    . "$PSScriptRoot\..\scripts\gen-docs-index.ps1"
}


Describe 'ConvertFrom-DocFrontmatter' {

    It '따옴표로 감싼 summary 를 벗겨 읽는다' {
        $text = @'
---
summary: "compose.yml 은 구조만, 값은 전부 `.env`"
---
# ADR-0001: 제목
'@
        $fm = ConvertFrom-DocFrontmatter -Text $text
        $fm['summary'] | Should -BeExactly 'compose.yml 은 구조만, 값은 전부 `.env`'
    }

    It '따옴표 없는 값도 그대로 읽는다' {
        $text = "---`nsummary: 따옴표 없는 요약`n---`n# 제목"
        (ConvertFrom-DocFrontmatter -Text $text)['summary'] | Should -BeExactly '따옴표 없는 요약'
    }

    It '값에 있는 콜론(:)·해시(#)를 따옴표 안에서 보존한다' {
        $text = '---' + "`n" + 'summary: "로드맵·버그를 Project #4·이슈로: 예외"' + "`n" + '---'
        (ConvertFrom-DocFrontmatter -Text $text)['summary'] |
            Should -BeExactly '로드맵·버그를 Project #4·이슈로: 예외'
    }

    It 'frontmatter 가 없으면 빈 해시테이블을 돌려준다' {
        $fm = ConvertFrom-DocFrontmatter -Text "# 제목만 있는 문서`n본문"
        $fm.Count | Should -Be 0
    }

    It '닫는 --- 뒤의 key: 는 읽지 않는다' {
        $text = @'
---
summary: "진짜 요약"
---
# 제목
noise: 본문에 있는 콜론 줄
'@
        $fm = ConvertFrom-DocFrontmatter -Text $text
        $fm['summary'] | Should -BeExactly '진짜 요약'
        $fm.ContainsKey('noise') | Should -BeFalse
    }

    It 'CRLF 줄바꿈에서도 동작한다' {
        $text = "---`r`nsummary: `"윈도우 줄바꿈`"`r`n---`r`n# 제목"
        (ConvertFrom-DocFrontmatter -Text $text)['summary'] | Should -BeExactly '윈도우 줄바꿈'
    }
}


Describe 'Get-DocH1' {

    It 'frontmatter 아래 첫 H1 을 읽는다' {
        $text = @'
---
summary: "x"
---
# ADR-0007: 공용 라이브러리 dot-source
## 배경
'@
        Get-DocH1 -Text $text | Should -BeExactly 'ADR-0007: 공용 라이브러리 dot-source'
    }

    It 'H2(##)는 제목으로 잡지 않는다' {
        Get-DocH1 -Text "## 소제목`n# 진짜제목" | Should -BeExactly '진짜제목'
    }
}


Describe 'Get-AdrTitle' {

    It 'ADR-NNNN: 접두사를 벗긴다' {
        Get-AdrTitle -H1 'ADR-0001: `.env`가 유일한 설정 소스' |
            Should -BeExactly '`.env`가 유일한 설정 소스'
    }

    It '접두사가 없으면 원문을 그대로 둔다' {
        Get-AdrTitle -H1 '접두사 없는 제목' | Should -BeExactly '접두사 없는 제목'
    }
}
