---
summary: "2019/2022 경로 차이를 `test -x`로 흡수"
---

# ADR-0006: sqlcmd 경로는 버전별로 런타임에 자동 판별한다

- 상태: Accepted
- 관련: [ADR-0003](0003-yaml-anchors-for-reuse.md), [ADR-0009](0009-password-via-env-var.md), `scripts/lib/_common.ps1` (`Get-SqlcmdInvocation`)

## 배경 (Context)

SQL Server 2019 와 2022 는 컨테이너 안 sqlcmd 위치가 다르다.

- 2019: `/opt/mssql-tools/bin/sqlcmd`
- 2022: `/opt/mssql-tools18/bin/sqlcmd -C` (`-C`는 서버 인증서 신뢰)

스크립트가 SQL을 실행할 때 인스턴스의 버전을 매번 사람이 지정하게 하면 번거롭고 틀리기 쉽다.
이미지가 갱신되며 경로가 또 바뀔 수도 있다.

## 결정 (Decision)

두 후보 경로를 `.env`의 `MSSQL_2019_SQLCMD` / `MSSQL_2022_SQLCMD`에 두고,
`_common.ps1`의 `Get-SqlcmdInvocation`이 **컨테이너 안에서 `test -x`로 실제 실행 가능한
경로를 확인**해 맞는 것을 고른다. 결과는 컨테이너별로 캐시한다.

- 헬스체크(compose.yml)는 버전별 앵커에서 각각 `${MSSQL_2019_SQLCMD}` / `${MSSQL_2022_SQLCMD}`를 쓴다.
- 스크립트 SQL 실행(backup/query/restore)은 `Get-SqlcmdInvocation`으로 버전을 **자동 판별**한다.

## 결과 (Consequences)

- **좋은 점**: 스크립트가 2019/2022를 구분하지 않아도 되고, 혼합 팜에서도 동일하게 동작한다.
- **좋은 점**: 이미지 경로가 바뀌면 **`.env` 두 줄만** 고치면 된다(스크립트·compose 불변).
- **감수할 점**: 후보 경로가 모두 실패하면 명확한 오류를 던진다 — `.env`의 경로 최신화가 필요하다.
- **감수할 점**: 판별을 위해 컨테이너당 `docker exec test -x` 한 번의 비용이 있다(캐시로 최소화).
