---
summary: "이미지 롤링 업데이트 — 하나씩 pull→재생성→healthy, 실패하면 그 지점에서 중단"
---

# update.ps1 — 이미지 롤링 업데이트

```powershell
.\scripts\update.ps1                            # 전체를 하나씩 롤링 갱신
.\scripts\update.ps1 -Service db2022a,db2022b   # 지정한 인스턴스만
.\scripts\update.ps1 -NoPull                    # pull 없이 현재 로컬 이미지로 재생성만
.\scripts\update.ps1 -Timeout 180               # healthy 대기 제한 시간(초) 조정
```

인스턴스를 **하나씩** `pull → 재생성 → healthy 확인` 순으로 갱신하고 다음으로 넘어갑니다.
한 번에 한 인스턴스만 내려갔다 올라오므로 나머지는 계속 서비스합니다(무중단에 가까움).
[restart.ps1 `-Recreate`](restart.md) 가 farm 전체를 동시에 내렸다 올리는 것과 대비됩니다.

**실패하면 그 지점에서 멈춥니다.** 이미 갱신한 인스턴스는 그대로 두고, 아직 손대지 않은
인스턴스는 건너뜁니다(SKIP) — 깨진 이미지를 farm 전체로 퍼뜨리지 않으려는 의도된 동작입니다.
마지막에 요약 표를 내고, 실패가 있으면 종료 코드 1을 반환합니다(스케줄러 감지용).
