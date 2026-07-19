---
summary: "[개발] 린트 + doctor + 문서 인덱스 검증 (+ `-Test`/`-Watch`) — 커밋 전 게이트"
---

# check.ps1 — 내부 개발 루프 검증 러너

운영이 아니라 **스크립트나 `compose` 설정을 편집할 때** 쓰는 로컬 검증 루프입니다. 실사용
운영에는 필요 없습니다. CI(`.github/workflows/ci.yml`)도 이 스크립트를 그대로 돌립니다.

```powershell
.\scripts\check.ps1                 # 린트 + doctor + 문서 인덱스 검증 1회
.\scripts\check.ps1 -Test           # 위 + Pester 단위 테스트까지
.\scripts\check.ps1 -Watch -Test    # 파일 저장 때마다 전체 루프 자동 재실행 (편집→즉시 피드백)
.\scripts\check.ps1 -Install        # 없는 개발 모듈(PSScriptAnalyzer/Pester)을 CurrentUser 로 설치
```

단계는 셋(+선택 하나)입니다.

1. **린트** — PSScriptAnalyzer 로 `scripts\`·`tests\` 의 모든 `.ps1` 정적 분석
2. **규약 점검** — [doctor.ps1](doctor.md) (+ Docker 가 켜져 있으면 compose 렌더링)
3. **문서 인덱스 검증** — [gen-docs-index.ps1 `-Check`](gen-docs-index.md)
4. `-Test` 를 주면 [test.ps1](test.md) 의 Pester 단위 테스트까지

- 오류가 하나라도 있으면 **종료 코드 1**을 반환합니다(CI/자동화 감지용).
- **개발 모듈은 선택 의존성**입니다. 없으면 해당 단계만 건너뛰고(노란 안내), `-Install`로
  부트스트랩합니다. 테스트는 **Pester 5 이상**이 필요합니다(Windows 기본 3.4.0 은 문법이 달라 쓰지 않음).
- 린트는 이 저장소 관례와 충돌하는 규칙 5개를 제외합니다(제외 이유는 `check.ps1` 의
  `$ExcludedRules` 주석 참고): `PSAvoidUsingWriteHost` · `PSUseSingularNouns` ·
  `PSReviewUnusedParameter` · `PSAvoidUsingPlainTextForPassword`(평문 SA 비밀번호는 의도된 설계 —
  [ADR-0013](../../.claude/adr/0013-plaintext-password-gitignored.md)) ·
  `PSUseShouldProcessForStateChangingFunctions`(수동 y/N 프롬프트 관례 — CONVENTIONS §9).
- **`compose/.env` 가 없으면**(gitignore 대상) doctor 단계가 멈춥니다. 값·규약만 검증할 땐
  `compose/.env.example` 을 복사해 `MSSQL_SA_PASSWORD` 만 정책 충족 더미로 채운 임시 `.env` 로
  돌리고 지웁니다(CI 도 같은 방식입니다).
