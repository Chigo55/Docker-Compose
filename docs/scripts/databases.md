---
summary: "DB 인벤토리 — 크기·복구 모델·최근 전체 백업 시각 (읽기 전용)"
---

# databases.ps1 — DB 인벤토리

어느 인스턴스에 어떤 DB가 있고, 데이터/로그 크기·복구 모델·최근 전체 백업 시각이 어떤지 한
표로 보여 줍니다. 백업 대상 파악과 용량 계획에 씁니다. 각 인스턴스에서 `sys.databases` +
`sys.master_files` + `msdb..backupset`을 조인해 조회하며, 아무것도 바꾸지 않습니다.

```powershell
.\scripts\databases.ps1                       # 전체 인스턴스의 사용자 DB 인벤토리
.\scripts\databases.ps1 -Service db2019c      # 특정 인스턴스만
.\scripts\databases.ps1 -Database MyDb        # 그 이름의 DB가 어느 인스턴스에 있는지
.\scripts\databases.ps1 -IncludeSystem        # 시스템 DB(master/tempdb/model/msdb)까지 포함
```

기본은 **사용자 DB만** 보여 줍니다(시스템 DB 제외). `-Database`로 이름을 주면 시스템/사용자
구분 없이 그 DB만 추립니다. **최근 백업**은 복구의 기준선인 "전체(Full)" 백업의 최신 완료
시각이며, 이력이 없으면 `(없음)`으로 표시합니다. 꺼진 인스턴스는 조회할 수 없어 `DOWN`,
조회에 실패하면 `FAIL`로 표시하고, 하나라도 성공하지 못하면 종료 코드 1을 반환합니다(스케줄러 감지용).
