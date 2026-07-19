---
summary: "`x-base`/`x-mssql-2019`/`x-mssql-2022`"
---

# ADR-0003: 공통 서비스 정의는 YAML 앵커로 재사용한다

- 상태: Accepted
- 관련: [ADR-0001](0001-env-single-source-of-truth.md), [ADR-0006](0006-sqlcmd-version-autodetect.md), `compose/compose.yml`

## 배경 (Context)

인스턴스 8개가 restart 정책·로깅·네트워크·헬스체크·환경변수를 거의 똑같이 공유한다.
서비스마다 이 설정을 그대로 복사하면 수십 줄이 중복되고, 정책 하나를 바꿀 때 모든
블록을 손봐야 한다.

## 결정 (Decision)

compose.yml 을 **재사용 조각(앵커) + 얇은 서비스 블록**으로 나눈다.

- `x-env(&env)`: 모든 컨테이너 공통 환경변수(EULA/비밀번호/PID/TZ).
- `x-healthcheck(&healthcheck)`: 헬스체크 주기·타임아웃·재시도 값.
- `x-base(&base)`: restart/stop_grace/네트워크/로깅 + `environment: *env`.
- `x-mssql-2019(&mssql2019)` / `x-mssql-2022(&mssql2022)`: `<<: *base`로 뼈대를 물려받고
  이미지 태그와 버전별 헬스체크 명령만 덮어쓴다.

각 서비스는 `<<: *mssql2019`(또는 `*mssql2022`)로 조각을 병합하고, **자기만의
`container_name`/`hostname`/`ports`/`volumes`만** 지정한다.

## 결과 (Consequences)

- **좋은 점**: 공통 정책은 한 곳(앵커)에서만 바꾸면 모든 인스턴스에 반영된다.
- **좋은 점**: 서비스 블록이 4줄로 짧아 인스턴스 추가 시 실수 여지가 작다.
- **감수할 점**: YAML 앵커 문법(`&`/`*`/`<<:`)을 모르면 파일이 낯설다 → 파일 상단에
  문법 안내 주석을 두어 보완한다.
- **감수할 점**: 2019/2022는 sqlcmd 경로가 달라 앵커를 둘로 나눠야 한다([ADR-0006](0006-sqlcmd-version-autodetect.md)).
