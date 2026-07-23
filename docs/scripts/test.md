---
summary: "[개발] Pester 단위 테스트 실행 (Pester 5+ 필요, Docker 불필요)"
---

# test.ps1 — 단위 테스트

`tests\` 폴더의 Pester 테스트를 실행합니다.

```powershell
.\scripts\test.ps1              # 단위 테스트만
.\scripts\test.ps1 -Install     # 없으면 Pester 5+ 를 CurrentUser 로 설치한 뒤 실행
.\scripts\check.ps1 -Test       # 린트·doctor·인덱스 검증까지 함께 (권장)
```

대상은 **Docker가 필요 없는 순수 로직**입니다 — `Read-DotEnv` 파싱, `Get-Instances` 자동 발견,
`Resolve-Services` 검증, 문서 frontmatter 파서 등. 순수 로직을 추가·수정했다면 테스트도 함께
씁니다([rules/authoring.md](../../.claude/rules/authoring.md)).

**Pester 5 이상**이 필요합니다. Windows 기본 3.4.0 은 문법이 달라 쓰지 않으며, 없으면 이 단계는
건너뜁니다(노란 안내). 실패가 있으면 종료 코드 1을 반환합니다.
