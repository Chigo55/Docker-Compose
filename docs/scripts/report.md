---
summary: "farm 상태를 한 장의 HTML 리포트로 저장 (읽기 전용)"
---

# report.ps1 — farm 상태 HTML 리포트

인스턴스 상태·최근 백업·DB 인벤토리를 한 장의 HTML로 모아 저장합니다. 아무것도 바꾸지 않는
조회 전용이라, 스케줄러로 주기 생성해 두고 브라우저로 farm 현황을 확인하는 용도로 좋습니다.

```powershell
.\scripts\report.ps1                                             # <DATA_ROOT>\_report\farm_<시각>.html 로 저장
.\scripts\report.ps1 -OutFile C:\docker\_report\farm.html -Open   # 경로 지정 + 브라우저로 열기
.\scripts\report.ps1 -NoSize                                     # 데이터 용량 계산 생략 (빠름)
```

터미널에서 바로 보고 싶을 때는 [status.ps1](status.md)·[databases.ps1](databases.md) 을 쓰세요.
