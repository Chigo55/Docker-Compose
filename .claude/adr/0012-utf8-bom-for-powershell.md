---
summary: "PS 5.1 한글 인코딩 사고 방지"
---

# ADR-0012: `.ps1`은 UTF-8 with BOM, docker 파일은 BOM 없음

- 상태: Accepted
- 관련: [ADR-0001](0001-env-single-source-of-truth.md), `scripts/*.ps1`, `compose/*`

## 배경 (Context)

이 저장소는 주석·사용자 출력이 모두 한국어다. 한국어 Windows 의 PowerShell 5.1 은
**BOM 이 없는 UTF-8 파일을 ANSI(CP949)로 잘못 읽는다.** 그러면 한글 주석·출력이 깨지고,
최악의 경우 파싱 자체가 실패한다. 반대로 Docker/compose 가 읽는 파일에 BOM 이 있으면
파서가 오작동할 수 있다.

## 결정 (Decision)

파일 종류별로 인코딩을 나눈다.

- **`.ps1` (PowerShell)**: **UTF-8 with BOM** 으로 저장한다. BOM 을 제거하는 편집기/도구로
  저장했다면 다시 UTF-8 BOM 으로 되돌린다.
- **`compose/.env`, `compose/compose.yml` (docker 가 읽음)**: **BOM 없이** 둔다. 값은 모두
  ASCII 로 하고, 한글은 주석에만 둔다.
- `.env`를 코드에서 읽을 때도 `Get-Content -Encoding UTF8`로 명시한다.

## 결과 (Consequences)

- **좋은 점**: PS 5.1 에서 한글이 안정적으로 표시되고 파싱 실패를 예방한다.
- **좋은 점**: Docker 도구가 compose/.env 를 문제없이 파싱한다.
- **감수할 점**: 편집기 설정이 인코딩을 바꾸지 않는지 주의해야 한다(특히 BOM 제거 자동화).
- **감수할 점**: 파일 종류마다 인코딩 규칙이 달라, 새 파일을 만들 때 어느 쪽인지 의식해야 한다.
