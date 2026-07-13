# ADR-0001: `.env`가 유일한 설정 소스, compose.yml 은 구조만 정의

- 상태: Accepted
- 관련: [ADR-0002](0002-instance-autodiscovery.md), [ADR-0003](0003-yaml-anchors-for-reuse.md), `compose/compose.yml`, `compose/.env.example`

## 배경 (Context)

SQL Server 인스턴스 여러 개를 한 호스트에서 운영하면, 포트·비밀번호·이미지 태그·데이터
경로 같은 값이 여러 곳에 흩어지기 쉽다. 값이 compose 파일과 스크립트 양쪽에 중복되면
한쪽만 고쳐 불일치가 나고, 그 불일치는 대개 "조용한 기동 실패"로 나타난다.

## 결정 (Decision)

**모든 설정값은 `compose/.env` 한 곳에만 둔다.** `compose/compose.yml`은 값이 아니라
**구조(어떤 서비스가 어떤 템플릿을 쓰고 어떤 변수를 주입받는가)만** 정의하고, 실제 값은
전부 `${VAR}` 치환으로 `.env`에서 가져온다. PowerShell 스크립트도 값을 하드코딩하지 않고
`Read-DotEnv`로 `.env`를 읽는다.

- 필수 값은 `${MSSQL_SA_PASSWORD:?...}`로 비면 즉시 실패시킨다.
- 선택 값은 `${TZ:-Asia/Seoul}`처럼 기본값을 준다.

## 결과 (Consequences)

- **좋은 점**: 값을 바꿀 때 고칠 곳이 `.env` 하나다. compose.yml 과 스크립트는 안정적이다.
- **좋은 점**: 팀에는 `.env.example`(값 비움)만 공유하고 실값 `.env`는 Git 제외([ADR-0013](0013-plaintext-password-gitignored.md)).
- **감수할 점**: `.env` 형식 규약(`$`→`$$`, 슬래시 경로, 인라인 주석 금지)을 사람이 지켜야 한다.
  이 위험은 [ADR-0010](0010-preflight-validation-doctor.md)의 `doctor.ps1`이 사전 점검으로 보완한다.
