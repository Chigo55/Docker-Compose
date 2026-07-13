# 비밀번호

- `MSSQL_SA_PASSWORD`는 `.env`에 평문으로 있고, 실값 `.env`는 `.gitignore` 대상이다.
  팀에는 값을 비운 `.env.example`만 공유한다([ADR-0013](../adr/0013-plaintext-password-gitignored.md)).
- 정책: **8자 이상 + 대문자/소문자/숫자/기호 중 3종 이상**.
- 비밀번호에는 **`$$`를 쓰지 말 것.** compose 는 `$$`→`$`로 해석하지만 스크립트(`Invoke-Sql`)는
  `.env` 원문을 그대로 쓰므로, `$$`가 있으면 backup/query/restore 인증이 어긋난다([ADR-0009](../adr/0009-password-via-env-var.md)).
