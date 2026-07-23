---
summary: "상태 표 — 컨테이너·헬스체크·포트 응답·데이터 용량 (읽기 전용)"
---

# status.ps1 — 상태 확인

컨테이너 상태, 헬스체크 결과, 포트 TCP 응답, 데이터 폴더 용량을 한 표로 보여줍니다.

```powershell
.\scripts\status.ps1
.\scripts\status.ps1 -Watch      # 5초마다 갱신
.\scripts\status.ps1 -NoSize     # 용량 계산 생략 (빠름)
```

healthy 로 안 바뀐다면 sqlcmd 경로가 바뀌었을 수 있습니다. `docs/README.md` 의
[문제 해결](../README.md#문제-해결)을 보세요. HTML 로 남기고 싶다면 [report.ps1](report.md) 이 있습니다.
