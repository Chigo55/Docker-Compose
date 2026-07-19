---
summary: "Pester/PSScriptAnalyzer 없으면 건너뜀, `-Install`"
---

# ADR-0014: 내부 개발 루프(check/test)는 선택 의존성으로 얹는다

- 상태: Accepted
- 관련: [ADR-0007](0007-shared-common-library.md), [ADR-0010](0010-preflight-validation-doctor.md), [ADR-0011](0011-batch-continue-on-error.md), [ADR-0012](0012-utf8-bom-for-powershell.md), `scripts/check.ps1`, `scripts/test.ps1`, `scripts/lib/_devtools.ps1`, `tests/`

## 배경 (Context)

스크립트가 늘면서 회귀 위험이 커졌다. 그러나 이 저장소는 빌드 산출물이 없는 ops 저장소라
무거운 CI/테스트 인프라나 "테스트를 위한 대규모 리팩터"는 성격에 맞지 않는다. 동시에,
운영자는 개발 도구(Pester/PSScriptAnalyzer) 없이도 스크립트를 그대로 쓸 수 있어야 한다.
즉 **검증 수단은 있되, 운영에는 부담을 주지 않아야** 한다.

## 결정 (Decision)

저장소를 **고칠 때만** 쓰는 로컬 개발 루프를 얹는다.

- `scripts/check.ps1`: 린트(PSScriptAnalyzer) + `doctor.ps1`(규약 + compose 렌더링)을 한 번에.
  `-Test`로 단위 테스트까지, `-Watch`로 파일 변경 시 자동 재실행. 실패 시 `exit 1`([ADR-0011](0011-batch-continue-on-error.md) 패턴).
- `scripts/test.ps1` + `tests/`: **Pester 5+** 로 순수 로직 단위 테스트. Docker가 필요한
  영역(백업/복원 실동작)은 일부러 대상에서 뺀다.
- **개발 모듈은 선택 의존성**: 없으면 그 단계만 건너뛰고(노란 안내) `-Install`로 부트스트랩한다.
  ([ADR-0010](0010-preflight-validation-doctor.md)에서 Docker가 꺼졌을 때 doctor가 경고만 내고 진행하는 것과 같은 태도.)
- **개발 전용 헬퍼는 `_devtools.ps1`로 분리**해 운영 라이브러리 `_common.ps1`([ADR-0007](0007-shared-common-library.md))에
  개발 의존성이 섞이지 않게 한다.
- 테스트는 `_common.ps1`의 상태 캐시(`$script:DotEnvCache`)에 사전을 직접 주입해, **I/O 분리
  리팩터 없이** 순수 발견/파싱 로직을 검증한다.
- `check.ps1`은 `doctor.ps1`/`test.ps1`을 **in-process `& script`** 로 호출한다. 호출 연산자로
  부른 스크립트의 `exit`는 부모를 죽이지 않고 `$LASTEXITCODE`만 남긴다(자식 프로세스는 컬러 출력 유실).

## 결과 (Consequences)

- **좋은 점**: 편집 → `check.ps1 -Watch -Test`로 즉시 피드백. 회귀를 빨리 잡는다.
- **좋은 점**: 운영 사용자는 개발 모듈 없이도 스크립트를 그대로 쓸 수 있다(도구 없으면 건너뜀).
- **좋은 점**: `exit 1` 규약으로 그대로 CI에 얹을 수 있다(남은 일은 GitHub Actions 워크플로 1개 — ROADMAP P3-9).
- **감수할 점**: Windows 기본 Pester 3.4.0 은 문법이 달라 쓰지 못하고 5+ 설치가 필요하다.
- **감수할 점**: Docker 실동작(백업/복원)은 단위 테스트 밖이다. 여기까지 넓히려면 I/O 분리 리팩터가 선행되어야 한다.
