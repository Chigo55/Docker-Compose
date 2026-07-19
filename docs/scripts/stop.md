---
summary: "정지 — 컨테이너는 남기고 멈춤 (제거는 down.ps1)"
---

# stop.ps1 — 정지

컨테이너를 정지합니다. 컨테이너 자체는 남으므로 [start.ps1](start.md) 로 다시 켤 수 있습니다.
컨테이너까지 지우려면 [down.ps1](down.md) 을 쓰세요.

```powershell
.\scripts\stop.ps1                     # 전체 정지 (컨테이너 유지)
.\scripts\stop.ps1 -Service db2019c    # 일부만
```

`restart: always` 정책이지만, **수동으로 `stop` 한 컨테이너는 Docker가 다시 켜지 않습니다.**
Docker Desktop을 재시작하면 실행 중이던 컨테이너만 자동 복귀합니다.
