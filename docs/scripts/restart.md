---
summary: "재시작 — `.env` 의 포트·이미지·볼륨 변경은 `-Recreate` 라야 반영"
---

# restart.ps1 — 재시작

```powershell
.\scripts\restart.ps1
.\scripts\restart.ps1 -Service db2022b
.\scripts\restart.ps1 -Recreate        # .env 변경분(포트·이미지·볼륨) 반영
```

**`.env`에서 포트나 이미지 태그를 바꿨다면 `restart`만으로는 반영되지 않습니다.** 컨테이너를
다시 만들어야 하므로 `-Recreate`를 쓰세요([rules/images-restart.md](../../.claude/rules/images-restart.md)).

`-Recreate`는 farm 전체를 동시에 내렸다 올립니다. 이미지 갱신처럼 한 번에 한 인스턴스씩
바꾸고 싶다면 [update.ps1](update.md) 이 낫습니다.
