---
summary: "백업 복원 — 최신 파일·`WITH MOVE` 자동, 체인(전체→차등→로그) 복원"
---

# restore.ps1 — 복원

[backup.ps1](backup.md) 의 짝입니다. 파일을 직접 붙이지 않고 `RESTORE DATABASE`를 실행합니다.
번거로운 부분을 자동화합니다.

- **백업 파일 자동 선택**: `<BACKUP_ROOT>\<컨테이너명>\<DB>_*.bak` 중 **가장 최신** 파일
- **논리 파일 자동 이동**: `RESTORE FILELISTONLY`로 백업 안의 논리 파일명을 읽어 `WITH MOVE`를
  자동 구성 → `/var/opt/mssql/data`로 배치
- **버전 자동 판별**: 2019/2022 sqlcmd 경로를 컨테이너에서 실제 확인 (`_common.ps1` 재사용)
- **활성 연결 정리**: 기존 DB가 있으면 `SINGLE_USER`로 연결을 끊고 `WITH REPLACE`로 덮어씀

```powershell
.\scripts\restore.ps1 -Service db2019c -Database MyDb          # 해당 인스턴스의 최신 백업 복원
.\scripts\restore.ps1 -Database MyDb                            # 전체 인스턴스에 각자의 최신 백업 복원
.\scripts\restore.ps1 -Service db2022b -BackupFile "C:\docker\_backup\Db2022B\MyDb_20260101_020000.bak"
.\scripts\restore.ps1 -Service db2019c -Database MyDb -NoRecovery  # 이후 로그 백업을 이어 복원 (RESTORING 유지)
.\scripts\restore.ps1 -Service db2019c -Database MyDb -Chain       # 최신 전체->차등->로그 체인 자동 복원
.\scripts\restore.ps1 -Service db2019c -Database MyDb -Force        # 확인 프롬프트 없이
.\scripts\restore.ps1 -Database MyDb -Force -NotifyWebhook <URL>   # 복원 요약을 Teams/Slack 웹훅으로 전송
```

복원은 대상 DB를 **덮어쓰는 파괴적 작업**이므로 `-Force`가 없으면 먼저 확인합니다. 한 인스턴스가
실패해도 나머지는 계속 진행하고, 실패가 있으면 종료 코드 1을 반환합니다. `-BackupFile`은 파일
하나를 뜻하므로 `-Service`로 인스턴스를 하나만 지정했을 때만 씁니다. `-Chain`은
`backup.ps1 -Type Diff/Log`로 만든 차등·로그 백업을 최신 전체 백업부터 순서대로 이어
복원합니다(중간 단계는 자동으로 `NORECOVERY`).

> 자동 복원은 데이터(`D`)·로그(`L`) 파일만 처리합니다. FILESTREAM 등 다른 유형이 있으면
> 중단하고 수동 복원을 안내합니다.
