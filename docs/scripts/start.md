---
summary: "기동 — `_DIR` 데이터 폴더를 먼저 만든 뒤 `compose up -d`"
---

# start.ps1 — 기동

`.env`의 `*_DIR`을 읽어 데이터 폴더를 먼저 만든 뒤 `compose up -d`를 실행합니다.
폴더가 없는 상태로 올리면 Docker가 빈 폴더를 만들어버려 기존 DB를 못 붙기 때문입니다.

```powershell
.\scripts\start.ps1                            # 전체 기동
.\scripts\start.ps1 -Pull                      # 이미지 최신본 받고 기동
.\scripts\start.ps1 -Recreate                  # 컨테이너 강제 재생성
.\scripts\start.ps1 -Service db2019c,db2022e   # 일부만
```

`MOUNT_LOG_SECRETS=true`면 `<DATA_ROOT>/<_DIR>/log`·`secrets` 폴더도 함께 만듭니다
(`compose/compose.yml` 쪽 마운트 주석도 함께 해제해야 합니다 — [rules/instances.md](../../.claude/rules/instances.md)).

기동 후 healthy 까지는 30~60초 걸립니다. 상태는 [status.ps1](status.md) 로 확인하세요.
