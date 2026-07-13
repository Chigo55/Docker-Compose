# ADR-0002: 인스턴스는 하드코딩하지 않고 `.env`에서 자동 발견한다

- 상태: Accepted
- 관련: [ADR-0001](0001-env-single-source-of-truth.md), [ADR-0007](0007-shared-common-library.md), `scripts/lib/_common.ps1` (`Get-Instances`)

## 배경 (Context)

인스턴스 개수는 환경마다 다르고(예시는 2019 3개 + 2022 5개), 시간이 지나며 늘거나 준다.
인스턴스 목록을 스크립트마다 배열로 박아두면, 인스턴스 하나를 추가할 때 여러 파일을
동시에 고쳐야 하고 빠뜨리기 쉽다.

## 결정 (Decision)

인스턴스 목록을 **어디에도 하드코딩하지 않는다.** `_common.ps1`의 `Get-Instances`가
`.env`에서 **`<PREFIX>_PORT` 키를 스캔**해(단 `MSSQL_PORT`는 내부 공통 포트이므로 제외)
인스턴스를 발견하고, 같은 접두사의 `_NAME`/`_DIR`을 함께 읽어 인스턴스 객체
(`Service`/`Name`/`Port`/`DataDir`)를 만든다.

- 규약: 한 인스턴스 = 접두사가 같은 **3종 세트** `<PREFIX>_NAME` / `<PREFIX>_PORT` / `<PREFIX>_DIR`.
- 서비스키 = `<PREFIX>`.ToLower() 이며, 이 값이 `compose.yml`의 서비스 키와 일치해야 한다.

## 결과 (Consequences)

- **좋은 점**: 인스턴스 추가 = `.env`에 3줄 + `compose.yml`에 서비스 블록. **스크립트는 손대지 않는다.**
- **좋은 점**: 모든 스크립트가 같은 목록을 보므로 대상 불일치가 없다.
- **감수할 점**: 발견 기준이 `_PORT` 키라, `_NAME`/`_DIR` 누락이나 접두사↔서비스키 불일치는
  런타임에야 드러난다. 이 위험은 [ADR-0010](0010-preflight-validation-doctor.md)의 `doctor.ps1`이
  3종 세트 완전성·서비스 키 양방향 일치로 사전 점검한다.
