---
summary: "SA 비밀번호 — 정책 · Git 제외 · `$$` 금지"
---

# 비밀번호

- `MSSQL_SA_PASSWORD`는 `.env`에 평문으로 있고, 실값 `.env`는 `.gitignore` 대상이다.
  팀에는 값을 비운 `.env.example`만 공유한다([ADR-0013](../adr/0013-plaintext-password-gitignored.md)).
- 정책: **8자 이상 + 대문자/소문자/숫자/기호 중 3종 이상**.
- 비밀번호에는 **`$$`를 쓰지 말 것.** compose 는 `$$`→`$`로 해석하지만 스크립트(`Invoke-Sql`)는
  `.env` 원문을 그대로 쓰므로, `$$`가 있으면 backup/query/restore 인증이 어긋난다([ADR-0009](../adr/0009-password-via-env-var.md)).

## GitHub 쪽 방어막과 그 한계

원격에는 **secret scanning + push protection 이 켜져 있다**([rules/github.md](github.md)). 토큰·API 키를
실수로 커밋하면 push 자체가 막힌다.

**다만 SA 비밀번호는 이 그물에 걸리지 않는다.** push protection 이 잡는 것은 형식이 뚜렷한 공급자
패턴(AWS 키 등)이고, 일반 비밀번호를 잡는 non-provider 패턴은 꺼져 있다. 즉 실값 `compose/.env` 를
막아 주는 것은 여전히 **`.gitignore` 하나뿐**이다. `.env` 를 강제로 add(`git add -f`)하거나 다른
이름으로 복사해 커밋하지 말 것.
