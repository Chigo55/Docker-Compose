---
summary: "컨테이너·네트워크 제거 — 데이터는 보존 (확인 프롬프트)"
---

# down.ps1 — 제거

컨테이너와 네트워크를 제거합니다. 되돌리기 어려운 작업이라 `-Force`가 없으면 영향 목록을
보여 주고 먼저 확인합니다.

```powershell
.\scripts\down.ps1                     # 컨테이너 + 네트워크 제거 (확인 프롬프트)
.\scripts\down.ps1 -Force              # 확인 없이
.\scripts\down.ps1 -RemoveImages       # 이미지까지 삭제
```

**데이터는 지워지지 않습니다.** 호스트 바인드 마운트(`DATA_ROOT`)에 있기 때문입니다
([rules/data-safety.md](../../.claude/rules/data-safety.md)). [start.ps1](start.md) 로 다시 올리면 기존 DB에 그대로 붙습니다.

정지만 하고 컨테이너를 남기려면 [stop.ps1](stop.md) 을 쓰세요.
