---
summary: "인스턴스 간 DB 복제 — copy-only 백업 + 복원 조합 (파괴적)"
---

# copy-db.ps1 — 인스턴스 간 DB 복제

[backup.ps1](backup.md)(copy-only 전체 백업) + [restore.ps1](restore.md) 을 조합해, 한 인스턴스의
DB를 다른 인스턴스로 한 번에 복제합니다. copy-only라 원본의 백업 체인(차등 기준 등)에는 영향을
주지 않습니다.

```powershell
.\scripts\copy-db.ps1 -From db2022a -To db2022b -Database MyDb                        # 같은 이름으로 복제
.\scripts\copy-db.ps1 -From db2022a -To db2022b -Database MyDb -AsDatabase MyDb_stg   # 다른 이름으로
.\scripts\copy-db.ps1 -From db2022a -To db2022a -Database MyDb -AsDatabase MyDb_clone # 같은 인스턴스 안에서 클론
```

`-To`의 대상 DB를 덮어쓰는 **파괴적 작업**이라 `-Force`가 없으면 먼저 확인합니다. 전송에 쓴
`.bak`은 `<BACKUP_ROOT>\<From 컨테이너>\`에 남습니다(보관 정책이 정리).
