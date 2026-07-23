---
summary: "로그 — compose 로그와 SQL Server 자체 errorlog(`-ErrorLog`)"
---

# logs.ps1 — 로그

```powershell
.\scripts\logs.ps1                     # 전체, 최근 100줄
.\scripts\logs.ps1 db2019c -Follow     # 실시간 추적
.\scripts\logs.ps1 db2022b -Tail 500
.\scripts\logs.ps1 -Since 30m          # 최근 30분치
.\scripts\logs.ps1 db2022e -ErrorLog   # SQL Server 자체 errorlog
```

컨테이너 stdout 로그는 기동/에러 요약 위주입니다. **로그인 실패나 복구 상세는 `-ErrorLog`로**
보세요 — 둘은 다른 로그입니다.

errorlog(`/var/opt/mssql/log`)는 기본적으로 마운트되지 않아 컨테이너와 함께 사라집니다.
호스트에 보존하려면 `MOUNT_LOG_SECRETS` 를 양쪽(`compose/.env` + `compose/compose.yml`) 켜세요
([운영 메모](../README.md#운영-메모)).
