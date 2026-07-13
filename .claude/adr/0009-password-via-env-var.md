# ADR-0009: SQL 비밀번호는 명령줄이 아니라 `SQLCMDPASSWORD` 환경변수로 전달한다

- 상태: Accepted
- 관련: [ADR-0005](0005-engine-based-backup.md), [ADR-0006](0006-sqlcmd-version-autodetect.md), `scripts/lib/_common.ps1` (`Invoke-Sql`)

## 배경 (Context)

컨테이너 안 sqlcmd 에 SQL을 실행하려면 sa 비밀번호를 넘겨야 한다. `sqlcmd -P <비밀번호>`처럼
명령줄에 직접 쓰면, 비밀번호에 든 특수문자(`!`, `$`, 공백 등)가 셸에서 확장·분해되어
인증이 어긋나거나 값이 프로세스 목록에 노출된다. SA 비밀번호 정책상 특수문자는 사실상 필수다.

## 결정 (Decision)

`_common.ps1`의 `Invoke-Sql`이 비밀번호를 `docker exec -e SQLCMDPASSWORD=<값>`으로
**환경변수로 주입**한다. sqlcmd 는 `-P` 없이도 `SQLCMDPASSWORD`를 읽는다. 아울러 `Invoke-Sql`은:

- `-b`로 오류 시 종료 코드를 0이 아니게 만들어 실패를 감지하고,
- `-h -1 -W`로 머리글·여분 공백 없이 출력해 파싱을 쉽게 하며,
- 선택 `-Separator`로 다중 컬럼 결과를 구분자로 나눠 파싱할 수 있게 한다(`restore.ps1`의
  `RESTORE FILELISTONLY`가 사용).

## 결과 (Consequences)

- **좋은 점**: 특수문자 비밀번호에서도 셸 인용 문제 없이 안정적으로 인증한다.
- **좋은 점**: 모든 스크립트 SQL 실행이 `Invoke-Sql` 하나를 거쳐 동작이 일관된다.
- **감수할 점**: `.env`의 값은 스크립트가 **원문 그대로** 쓰므로, compose 이스케이프용 `$$`가
  비밀번호에 들어가면 스크립트 인증과 어긋난다(`doctor.ps1`이 `$$` 포함을 경고).
