---
summary: "대화형 sqlcmd 세션 — 대상은 정확히 하나여야 함"
---

# shell.ps1 — 대화형 sqlcmd 세션

임시 확인·수정을 하려고 매번 긴 `docker exec -it ... sqlcmd ...`를 치는 수고 없이, 서비스 키
하나로 해당 인스턴스에 sqlcmd 프롬프트(`1>`)를 바로 엽니다. 버전(2019/2022)과 비밀번호는
`_common.ps1`이 자동 처리하며, `-P` 대신 `SQLCMDPASSWORD` 환경변수로 접속합니다.

```powershell
.\scripts\shell.ps1 -Service db2019c              # db2019c 에 master 로 접속
.\scripts\shell.ps1 db2022b -Database MyDb        # 서비스 키는 첫 인자로도 받음, 기본 DB 지정
```

대화형 세션이라 대상은 **정확히 하나**여야 합니다. 인스턴스가 2개 이상이면 `-Service`로 하나를
지정하세요. 세션 종료는 프롬프트에서 `EXIT`/`QUIT`(또는 Ctrl+C).

여러 인스턴스에 같은 질의를 한 번에 돌리려면 [query.ps1](query.md) 을 쓰세요.
